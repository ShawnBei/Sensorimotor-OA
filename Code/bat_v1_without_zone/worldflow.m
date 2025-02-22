

function [Xnew, Ynew, Znew] = worldflow(oldXYZ, deta_az, deta_el, movement)

rads = deta_el;
Rot1 = [1   0           0;
        0   cos(rads)   -sin(rads);
        0   sin(rads)   cos(rads)];

rads = deta_az;
Rot2 = [cos(rads)   0   sin(rads);
        0           1   0;
        -sin(rads)  0   cos(rads)];

% world_rot_new = world_rot * Rot1 * Rot2;

newXYZ = (Rot2 *Rot1 * oldXYZ')';
% newXYZ = ( newXYZ)';

Xnew = newXYZ(:,1);
Ynew = newXYZ(:,2);
Znew = newXYZ(:,3) - movement;

% Rot1
% Rot2

end








