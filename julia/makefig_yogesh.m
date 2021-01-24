
load result_p2_l6.mat
f0 = flipdim(permute(f0, [2 1 3]),2);
fp = flipdim(permute(fp, [2 1 3]),2);
g0 = flipdim(permute(g0, [2 1 3]),2);
gp = flipdim(permute(gp, [2 1 3]),2);
gp_p2_l6 = gp .* mask;
fp_p2_l6 = fp .* mask;

load result_p10_l6.mat
f0 = flipdim(permute(f0, [2 1 3]),2);
fp = flipdim(permute(fp, [2 1 3]),2);
g0 = flipdim(permute(g0, [2 1 3]),2);
gp = flipdim(permute(gp, [2 1 3]),2);
gp_p10_l6 = gp .* mask;
fp_p10_l6 = fp .* mask;

g0 = g0 .* mask;
f0 = f0 .* mask;

y = 9:56;
x = 7:56;
z = 3;

g0 = g0(x,y,z);
gp_p2_l6 = gp_p2_l6(x,y,z);
gp_p10_l6 = gp_p10_l6(x,y,z);

figure(1);
im(cat(1,g0, gp_p2_l6, gp_p10_l6), [-20 100]); colormap jet;
h = colorbar; h.TickLabels{end} = 'Hz/cm'; axis off; title '';
print -djpeg g.png
figure(2);
im(cat(1,f0, fp_p2_l6, fp_p10_l6), [-100 100]); colormap jet;
h = colorbar; h.TickLabels{end} = 'Hz'; axis off; title '';
print -djpeg b0.png

max(abs([g0(:) gp_p2_l6(:) gp_p10_l6(:)]))
