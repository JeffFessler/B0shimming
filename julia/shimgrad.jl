using MAT, JLD2
using MIRT: embed!, jim, ndgrid
using Plots
#using LinearAlgebra
#using SparseArrays

include("getSHbasis.jl")
include("getSHbasisGrad.jl")
include("getcalmatrix.jl")
include("shimoptim.jl")
include("fieldgrad.jl")


############################################################################################
## EDIT this section

# Shim calibration data
calFile = "CalibrationDataSiemensMGH12Dec2020.jld2"
calFile = "CalibrationDataUM10Dec2020.jld2"; 

# shim system current limits
shimlims = (100*ones(3,), 4000*ones(5,), 12000)   # (lin max, hos max, sum hos max)

# baseline field map, fov, and mask. See mat2jld2.jl.
f0File = "Psub1_localmask.jld2"   
f0File = "Psub1.jld2"   
f0File = "Psub1_z41_70.jld2"

# order of spherical harmonic basis
# for linear shimming, set l = 1
l = 4

# Loss (objective) function for optimization.
# The field map f is modeled as f = H*A*s + f0, where
#   s = shim amplitudes (vector), 
#   H = spherical harmonic basis functions
#   A = matrix containing shim coil expansion coefficients for basis in H
#   f0 = baseline field map at mask locations (vector)
# The fieldmap gradient g is thus g = gH*A*s + df0, where
#   gH is the gradient of the basis

# Loss based on B0 field gradients
function loss1(s, gHxA, gHyA, gHzA, g0x, g0y, g0z) 
	# TODO: account for non-isotropic voxel size
	g = map( (gx,gy,gz) -> norm([gx,gy,gz],2), gHxA*s + g0x, gHyA*s + g0y, gHzA*s + g0z)
	# g = map( gy -> norm(gy,2), gHyA*s + g0y)
	gy = gHyA*s + g0y
	N = length(g0x[:])
	#@show [norm(gy,6)^6 norm(g, 8)^8]/N
	beta = 1e5
	#return (norm(gy, 6)^6 + beta * norm(g, 2)^2) / N
	return (0*norm(gy, 6)^6 + norm(g, 2)^2) / N
	#return norm(g, Inf) 
end

# Loss based on p-norm of B0 field
function loss2(s, HA, f0) 
	p = 8
	c = norm(HA*s + f0, p)^p / length(f0)
	#@show c 
	return c
end

function loss2(s, HA, f0, p) 
	c = norm(HA*s + f0, p)^p / length(f0)
	return c
end

############################################################################################



############################################################################################
# Load calibration data and calculate calibration matrix A
############################################################################################

# For 2nd order shims: 
# F = [nx ny nz 8] (Hz), in order 'x', 'y', 'z', 'z2', 'xy', 'zx', 'x2y2', 'zy'
# S = [8 8], shim amplitudes used to obtain F (hardware units)
@load "$calFile" F S fov mask

mask = BitArray(mask)

if l < 2
	F = F[:,:,:,1:3]
	s = diag(S)
	S = Diagonal(s[1:3])
end

# 0th-2nd order terms in getSHbasis.jl are in order [dc z x y z2 zx zy x2y2 xy],
# so reorder F to match that.
# No need to reorder S
inds = [3, 1, 2, 4, 6, 8, 7, 5] 
Fr = copy(F)
for ii = 1:size(F,4)
	Fr[:,:,:,ii] = F[:,:,:,inds[ii]]
end
F = Fr

N = sum(mask[:])

(nx,ny,nz,nShim) = size(F)

(x,y,z) = ndgrid(
	range(-fov[1]/2, fov[1]/2, length=nx), 
	range(-fov[2]/2, fov[2]/2, length=ny), 
	range(-fov[3]/2, fov[3]/2, length=nz) 
	)

# mask F and reshape to [N 8] 
Fm = zeros(N, nShim)
for ii = 1:nShim
	f1 = F[:,:,:,ii]
	Fm[:,ii] = f1[mask]
end

# Get spherical harmonic basis of degree l
H = getSHbasis(x[mask], y[mask], z[mask], l)   # size is [N sum(2*(0:l) .+ 1)]

# Get calibration matrix A
A = getcalmatrix(Fm, H, diag(S))



############################################################################################
# Now that A is determined we can use it to optimize shims for a given acquired fieldmap f0.
############################################################################################

@load "$f0File" f0 fov mask

(nx,ny,nz) = size(f0)

mask = BitArray(mask)

(g0x,g0y,g0z) = fieldgrad(fov, f0);

g0xm = g0x[mask]
g0ym = g0y[mask]
g0zm = g0z[mask]

N = sum(mask[:])

(x,y,z) = ndgrid(
	range(-fov[1]/2, fov[1]/2, length=nx), 
	range(-fov[2]/2, fov[2]/2, length=ny), 
	range(-fov[3]/2, fov[3]/2, length=nz) 
	)

@time (gHx, gHy, gHz) = getSHbasisGrad(x[mask], y[mask], z[mask], l)  
H = getSHbasis(x[mask], y[mask], z[mask], l)  

W = Diagonal(ones(N,))   # optional spatial weighting

#s0 = [57, 48, 52, 2, 2000, 1, -18, 115, 87]
if false
	@time shat = shimoptim(W*gHx*A, W*gHy*A, W*gHz*A, g0xm, g0ym, g0zm, shimlims, loss1)
else
	@time shat = shimoptim(W*H*A, f0[mask], shimlims; loss=loss2, ftol_rel = 1e-3)
end

@show loss1(0*shat, W*gHx*A, W*gHy*A, W*gHz*A, g0xm, g0ym, g0zm)   # loss before optimization
@show loss1(  shat, W*gHx*A, W*gHy*A, W*gHz*A, g0xm, g0ym, g0zm)   # loss after contrained optimization
@show loss2(0*shat, W*H*A, f0[mask], 2)
@show loss2(  shat, W*H*A, f0[mask], 2)

@show Int.(round.(shat))

shat_ge = Int.(round.(shat))
shat_siemens = round.(shat; digits=1)

println("\nRecommended shim changes:") 

println(string(
	"\tcf, x, y, z = ", 
	shat_ge[1], ", ",
	shat_ge[3], ", ", 
	shat_ge[4], ", ", 
	shat_ge[2])) 

if length(shat) > 4
	println(string("\t",
		"z2 ", shat_ge[5],
		" zx ", shat_ge[6], 
		" zy ", shat_ge[7], 
		" x2y2 ", shat_ge[8], 
		" xy ", shat_ge[9]))

println(" ")
println(string(
	"GE: ",
	"\tset cf, x, y, z shims in Manual Prescan"));
	println(string(
		"\tsetNavShimCurrent",
		" z2 ", shat_ge[5],
		" zx ", shat_ge[6], 
		" zy ", shat_ge[7], 
		" x2y2 ", shat_ge[8], 
		" xy ", shat_ge[9]))
	println(" ")
	println(string(
		"Siemens: adjvalidate -shim -set -mp -delta ",
		shat_siemens[3], " ",
		shat_siemens[4], " ",
		shat_siemens[2], " ",
		shat_siemens[5], " ",
		shat_siemens[6], " ",
		shat_siemens[7], " ",
		shat_siemens[8], " ",
		shat_siemens[9]))
else
	println(string(
		"\tSiemens: adjvalidate -shim -set -mp -delta ",
		shat_siemens[3], " ",
		shat_siemens[4], " ",
		shat_siemens[2]))
end

# predicted fieldmap after applying shims
fp = zeros(size(f0))
H = getSHbasis(x[mask], y[mask], z[mask], l)
fpm = H*A*shat + f0[mask]
embed!(fp, fpm, mask)   

# predicted fieldmap gradients after applying shims
gpx = zeros(size(f0))
gpy = zeros(size(f0))
gpz = zeros(size(f0))
gpxm = gHx*A*shat + g0x[mask]
gpym = gHy*A*shat + g0y[mask]
gpzm = gHz*A*shat + g0z[mask]
embed!(gpx, gpxm, mask)   
embed!(gpy, gpym, mask)   
embed!(gpz, gpzm, mask)   

# net gradient before and after applying shims
g0 = map( (gx,gy,gz) -> norm([gx,gy,gz]), g0x, g0y, g0z)
gp = map( (gx,gy,gz) -> norm([gx,gy,gz]), gpx, gpy, gpz)

# display original and predicted fieldmap gradients
#pyplot()
clim = (-50,50)
p1 = jim(cat(g0x.*mask, gpx.*mask; dims=1); clim=clim, color=:jet)
p2 = jim(cat(g0y.*mask, gpy.*mask; dims=1); clim=clim, color=:jet)
p3 = jim(cat(g0z.*mask, gpz.*mask; dims=1); clim=clim, color=:jet)
clim = (-70,70)
p4 = jim(cat( g0.*mask,  gp.*mask; dims=1), "B0 gradient (net)"; clim=clim, color=:jet)

p = plot(p1, p2, p3, p4, layout=(2,2))
display(p4)

@show [maximum(g0[mask]) maximum(gp[mask])]
@show [maximum(g0y[mask]) maximum(gpy[mask])]