function output = batflight25(settings)

log_gain_doppler = settings.log_gain_doppler;
delay_window = settings.delay_window;
iteration_steps = settings.iteration_steps;
doplot = settings.doplot;
reflectors = settings.reflectors;
gorandom = settings.gorandom;
worldshape = settings.worldshape;
maxdist = settings.maxdist;
fov = settings.fovea;
earsfixed = settings.earsfixed;
earsfixed_off_axis = settings.earsfixed_off_axis;
max_vel = settings.linear_velocity;
attenuation_range = settings.attenuation_range;
emission_freq = settings.emission_freq;
rand_phase = settings.rand_phase;
max_slope = settings.max_slope;
constrained = settings.constrained;
system = settings.system;

if strcmp(system,'CF')
    [L1,R1]=get_hrtf(-15,30,emission_freq);
    [L2,R2]=get_hrtf(15,0,emission_freq);
    [L3,R3]=get_hrtf(0,15,emission_freq);
end

if strcmp(system,'FM');
    [L1,R1]=get_hrtf_phillo(-10,+20,emission_freq);
    [L3,R3]=get_hrtf_phillo(+05,+05,emission_freq);
end

if earsfixed == 1 && earsfixed_off_axis == 0;
    L1 = L3;
    R1 = R3;
    L2 = L3;
    R2 = R3;
end

X=reflectors(:,1);Y=reflectors(:,2);Z=reflectors(:,3);
[az,el,objrange]= mycart2sph(X,Y,Z);

bat_pos = [0 0 0];
bat_rot = eye(3);

steermatlog = NaN(iteration_steps,2);
batposlog=NaN(iteration_steps,3);
objdistlog = NaN(iteration_steps,1);
handlelog = NaN(iteration_steps,1);
ipi_log = NaN(iteration_steps,1);
rotation_log_az =NaN(iteration_steps,3);
rotation_log_el =NaN(iteration_steps,3);
velocities = NaN(iteration_steps,1);
reflectors = NaN(iteration_steps,2);

if doplot==0;mymovie=NaN;end
last_wandering = Inf;
linear_velocity = max_vel;
reaction_time = 50/1000;

for iteration =1:iteration_steps
    VS=1;if strcmp(system,'FM');VS=0;end;
    reflector_strenght = randrange(min(attenuation_range(:)),max(attenuation_range(:)),size(az));
    
    if earsfixed_off_axis
        LEFT = call(L1,az,el,objrange,linear_velocity*VS,emission_freq,delay_window,fov,reflector_strenght);
        RIGHT= call(R1,az,el,objrange,linear_velocity*VS,emission_freq,delay_window,fov,reflector_strenght);
        options = [1 -1;-1 1];
    else
        if mod(iteration,2)==0;
            LEFT = call(L1,az,el,objrange,linear_velocity*VS,emission_freq,delay_window,fov,reflector_strenght);
            RIGHT= call(R1,az,el,objrange,linear_velocity*VS,emission_freq,delay_window,fov,reflector_strenght);
            options = [1 -1;-1 1];
        else
            LEFT = call(L2,az,el,objrange,linear_velocity,emission_freq,delay_window,fov,reflector_strenght);
            RIGHT= call(R2,az,el,objrange,linear_velocity,emission_freq,delay_window,fov,reflector_strenght);
            options = [1 1;-1 -1];
        end
    end
    
    %log doppler and gain for left ear
    if log_gain_doppler == 1;
        doppler = LEFT.shift;
        gain = LEFT.gains_linear;
        gain_log{iteration} = gain;
        doppler_log{iteration} = doppler;
    end
    
    %get object distances
    objdist_L = LEFT.range;
    objdist_R = RIGHT.range;
    objdist = [objdist_L(:);objdist_R(:)];
    if isempty(objdist);objdist=1000;end;
    if isnan(objdist);objdist=1000;end;
    closest_distance = min(objdist);
    
    %set new timescale, magnitude and lineair velocity
    %
    
    %ipi = 2*(closest_distance/343) + 0.03;
    %if ipi > 0.1 ;ipi=0.1;end;
    %if ipi < 0.06;ipi = 0.05;end
    ipi = 0.1;
    
    linear_velocity = interp1([2000 5 0],[max_vel max_vel 0.3],closest_distance);
    if isnan(linear_velocity);linear_velocity=max_vel;end
    
    magnitude = interp1([0 10],[666 -500],linear_velocity);
    if magnitude<0;magnitude=0;end
    
    %set  rotation time and processing time
    processing_time = 2*(closest_distance/343) + reaction_time + delay_window;
    rotation_time = ipi - processing_time;
    if rotation_time < 0;rotation_time = 0;end
    if processing_time > ipi;processing_time=ipi;end
    
    %bat steering--------
    if rand_phase==1;
        leftgains = LEFT.gains_linear.*exp(sqrt(-1)*randrange(-pi,pi,size(LEFT.gains_linear)));
        rightgains = RIGHT.gains_linear.*exp(sqrt(-1)*randrange(-pi,pi,size(RIGHT.gains_linear)));
    end
    if rand_phase==0;
        leftgains = LEFT.gains_linear.*exp(sqrt(-1)*randrange(0,0,size(LEFT.gains_linear)));
        rightgains = RIGHT.gains_linear.*exp(sqrt(-1)*randrange(0,0,size(RIGHT.gains_linear)));
    end
    
    nr_reflectors = [sum(LEFT.gains > 0) sum(RIGHT.gains > 0)];
    
    steermat = [abs(sum(leftgains)),abs(sum(rightgains))];
    steermat = 20*log10(steermat/(2*10.^-5));
    steermat(isinf(steermat))=0;
    [~,minindex]=min(steermat);
    current_az_sign = options(minindex,1);
    current_el_sign = options(minindex,2);
    
    if gorandom>0;current_az_sign = randsample([-1,1],1);current_el_sign = randsample([-1,1],1);end
    if gorandom>1;magnitude = randrange(0,magnitude,[1 1]);end;
    if earsfixed == 1;current_el_sign = randsample([-1,1],1);end
    
    %scale azimuth and elevation rotation with rotation time
    current_az=current_az_sign*magnitude*rotation_time;
    current_el=current_el_sign*magnitude*rotation_time;
    
    %apply elevation and azimuth constraints
    if strcmp(worldshape,'H');current_el=0;end;
    if strcmp(worldshape,'V');current_az=0;end;
    %if strcmp(worldshape,'T');current_el=0;end;
    if strcmp(worldshape,'R1');current_el=0;end;
    if strcmp(worldshape,'R2');current_el=0;end;
    if strcmp(worldshape,'MH');current_el=0;end;
    if strcmp(worldshape,'MV');current_az=0;end;
    
    %constrain elevation
    if current_el > 0;el_step = -5;end;
    if current_el < 0;el_step =  5;end;
    while 1
        rads = deg2rad(current_el);Rot1 = [1 0 0;0 cos(rads) sin(rads);0 -sin(rads) cos(rads)];
        rads = deg2rad(current_az);Rot2 = [cos(rads) 0 sin(rads);0 1 0;-sin(rads) 0 cos(rads)];
        predicted_bat_rot = bat_rot *  Rot1 * Rot2;
        pointing_vector = predicted_bat_rot*[0;0;1];
        alpha = [0 1 0] * pointing_vector; %dot product (single number)
        angle_y = rad2deg(acos(alpha)); %angle with y vector
        world_elevation = 90 - angle_y;
        %disp([angle_y world_elevation])
        elevation_ok = inrange(world_elevation,[-max_slope max_slope]);
        if constrained==0;break;end
        if elevation_ok;break;end
        current_el = current_el + el_step;
    end
    
    
    %wandering handling
    last_wandering = last_wandering + 1;
    is_wandering = 0;
    if ~strcmp(worldshape(1),'R') && sqrt(sum(bat_pos.^2))>(maxdist-0.15);is_wandering = 1;end
    if strcmp(worldshape(1),'R') && ~point_within(bat_pos,X,Y,Z) == 1;is_wandering = 1;end
    
    if is_wandering == 1;
        homepos = bat_pos*-bat_rot;
        [home_az,home_el,~]=mycart2sph(homepos(1),homepos(2),homepos(3));
        current_az = home_az;
        current_el = -home_el;
        rotation_time = 0.1;
        handlelog(iteration-1)=1;
        last_wandering = 0;
    end
    
    if last_wandering>1
        %move world--during processing and wait
        movement = linear_velocity * processing_time;
        [az,el,objrange]=flow([az el objrange],0,0,movement);
        %move bat--during processing and wait
        rads = deg2rad(0);Rot1 = [1 0 0;0 cos(rads) sin(rads);0 -sin(rads) cos(rads)];
        rads = deg2rad(0);Rot2 = [cos(rads) 0 sin(rads);0 1 0;-sin(rads) 0 cos(rads)];
        displacement = bat_rot * (Rot1 * Rot2 * [0;0;1]);
        bat_rot = bat_rot *  Rot1 * Rot2;
        bat_pos = bat_pos + displacement' * movement;
    end
    %move world--during rotation time
    movement = linear_velocity * rotation_time;
    [az,el,objrange]=flow([az el objrange],current_az,current_el,movement);
    %move bat--during rotation time
    rads = deg2rad(current_el);Rot1 = [1 0 0;0 cos(rads) sin(rads);0 -sin(rads) cos(rads)];
    rads = deg2rad(current_az);Rot2 = [cos(rads) 0 sin(rads);0 1 0;-sin(rads) 0 cos(rads)];
    displacement = bat_rot * (Rot1 * Rot2 * [0;0;1]);
    bat_rot = bat_rot *  Rot1 * Rot2;
    bat_pos = bat_pos + displacement' * movement;
    
    %logging
    reflectors(iteration,:) = nr_reflectors;
    steermatlog(iteration,:)=steermat;
    objdistlog(iteration) = closest_distance;
    batposlog(iteration,:)=bat_pos;
    ipi_log(iteration)=ipi;
    rotation_log_az(iteration) = current_az;
    rotation_log_el(iteration) = current_el;
    velocities(iteration) = linear_velocity;
    displayinfo = [iteration_steps current_az current_el];
    str =sprintf('%+03.2f\t\t',displayinfo);disp(str);
end
output.reflectors = reflectors;
output.velocities = velocities;
output.batposlog = batposlog;
output.steermatlog = steermatlog;
output.objdistlog = objdistlog;
output.mymovie = mymovie;
output.LEFT = LEFT;
output.RIGHT = RIGHT;
output.objrange = objrange;
output.objdist = objdist;
output.handlelog = handlelog;
output.ipi_log = ipi_log;
output.rotation_log_az = rotation_log_az;
output.rotation_log_el = rotation_log_el;

if log_gain_doppler==1;save('log.mat','gain_log','doppler_log');end

end