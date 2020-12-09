using SphericalHarmonics
using CoordinateTransformations: SphericalFromCartesian
using MIRT: ndgrid, jim
using ForwardDiff
using Plots

"""
	Get spherical harmonic basis of order L, and its gradient, evaluated at spatial locations x, y, z
"""
function getSHbasis(
	x::Vector{<:Real}, 
	y::Vector{<:Real}, 
	z::Vector{<:Real}, 
	L::Int64
	)

	# vector of position vectors (needed to calculate gradient)
	r = map( (x,y,z) -> [x, y, z], x, y, z)

	# function evaluates spherical harmonic at one spatial location r = [x, y, z]
	c2s = SphericalFromCartesian()
	function sh(r, l, m)
		a = c2s(r)
		(rho, ϕ, θ) = (a.r, a.θ, π/2 - a.ϕ)    # (radius, azimuth, colatitude)
		Y = computeYlm(θ, ϕ; lmax=l)
		rho^l * Y[(l,m)]
	end

	# SH basis
	H = zeros(size(x,1), sum(2*(0:L) .+ 1))
	#=
	Hx = zeros(size(x,1), sum(2*(0:L) .+ 1))
	Hy = zeros(size(x,1), sum(2*(0:L) .+ 1))
	Hz = zeros(size(x,1), sum(2*(0:L) .+ 1))
	=#
	ic = 1
	for l = 0:L
		for m = -0:l
			# SH evaluated at r
			f = map( r -> sh(r, l, m), r)
			H[:,ic] = real(f)    

			#= gradient evaluated at r
			sh1 =  r -> real(sh(r, l, m))
			g = r -> ForwardDiff.gradient(sh1, r)
			df = map( r -> g(r), r)
			Hx[:,ic] = map( r -> r[1], df)
			Hy[:,ic] = map( r -> r[2], df)
			Hz[:,ic] = map( r -> r[2], df)
			=#

			ic = ic+1
			if m != 0
				H[:,ic] = imag(f)

				#=
				sh1 =  r -> imag(sh(r, l, m))
				g = r -> ForwardDiff.gradient(sh1, r)
				df = map( r -> g(r), r)
				Hx[:,ic] = map( r -> r[1], df)
				Hy[:,ic] = map( r -> r[2], df)
				Hz[:,ic] = map( r -> r[2], df)
				=#

				ic = ic+1
 			end
 		end
 	end

	if false
	x = x[:]
	y = y[:]
	z = z[:]
	H = [ones(length(x),) x y z z.^2-1/2*(x.^2+y.^2) x.*y z.*x x.^2-y.^2 z.*y]
	end

	H
end

# test function
function getSHbasis(str::String)

	(nx,ny,nz) = (40,40,20)
	rx = range(-10,10,length=nx)
	ry = range(-10,10,length=ny)
	rz = range(-10,10,length=nz)
	(x,y,z) = ndgrid(rx,ry,rz)

	l = 2
	H = getSHbasis(x[:], y[:], z[:], l)

	H = reshape(H, nx, ny, nz, size(H,2))

	# compare with cartesian expressions
	x = x[:]
	y = y[:]
	z = z[:]
	Hcart = [z.^2-1/2*(x.^2+y.^2) x.*y z.*x x.^2-y.^2 z.*y]
	Hcart = reshape(Hcart, nx, ny, nz, size(Hcart,2))
	#p1 = jim(cat(H[:,:,:,5:9],Hcart;dims=1))
	p1 = jim(H[:,:,:,5:9])
	p2 = jim(Hcart)
	p = plot(p1, p2)
	display(p)
end

