function [T, GRID, PARA, SEB, BALANCE] = CryoGridSnow(T, GRID, FORCING, SEB, PARA, c_temp, timestep, BALANCE)

if sum(isnan(GRID.snow.Snow_i(:)))>0
    fprintf('NaN in GRID.snow.Snow_i - CGS flag00000\n')
end
if sum(isnan(GRID.snow.Snow_a(:)))>0
    fprintf('NaN in GRID.snow.Snow_a - CGS flag0\n')
end


if ~isempty(GRID.snow.cT_domain_ub) %snow cover already exitis
    
    %----------calculate snow surface albedo ------------------------------
    
    if max(T(GRID.snow.cT_domain))>=0    % melting conditions
        PARA.snow.albedo = PARA.snow.min_albedo + (PARA.snow.albedo - PARA.snow.min_albedo) ...
            .* exp(-PARA.snow.tau_f .* timestep.*24.*3600 ./ PARA.snow.tau_1);
    else
        PARA.snow.albedo=max(PARA.snow.albedo-PARA.snow.tau_a.*timestep.*24.*3600./PARA.snow.tau_1, PARA.snow.min_albedo);
    end
    
    %--------SEB.sublimation-----------------------------------------------
    
    if sum(isnan(GRID.snow.Snow_i(:)))>0
        fprintf('NaN in GRID.snow.Snow_i - CGS flag0\n')
    end
    
    if isnan(SEB.Qe)==1;
        fprintf('CGsnow : SEB.Qe is NaN\n')
    end

    if isnan(SEB.Qe)==0;
        GRID.snow.Snow_i(GRID.snow.cT_domain_ub) = GRID.snow.Snow_i(GRID.snow.cT_domain_ub) ...
            - SEB.Qe.*timestep.*24.*3600./PARA.constants.L_sg./PARA.constants.rho_i;%- SEB.Qe.*timestep.*24.*3600./(L+L_lv)./1000;
    end
    
    if sum(isnan(GRID.snow.Snow_i(:)))>0
        fprintf('NaN in GRID.snow.Snow_i - CGS flag1\n')
    end
    
    if sum(isnan(GRID.snow.Snow_a(:)))>0
        fprintf('NaN in GRID.snow.Snow_a - CGS flag1\n')
    end
    
    if (GRID.snow.Snow_i(GRID.snow.cT_domain_ub)+GRID.snow.Snow_w(GRID.snow.cT_domain_ub)+GRID.snow.Snow_a(GRID.snow.cT_domain_ub))>0 && isnan(SEB.Qe)==0;
        
        nonAirFractionUppermostGridCell = (GRID.snow.Snow_i(GRID.snow.cT_domain_ub)+GRID.snow.Snow_w(GRID.snow.cT_domain_ub))./...
            (GRID.snow.Snow_i(GRID.snow.cT_domain_ub)+GRID.snow.Snow_w(GRID.snow.cT_domain_ub)+GRID.snow.Snow_a(GRID.snow.cT_domain_ub));
        
        if nonAirFractionUppermostGridCell==0;
            fprintf('nonAir est nul\n')
        elseif isnan(nonAirFractionUppermostGridCell)==1;
            
            fprintf('nonAir est NaN\n')
        end
        
        GRID.snow.Snow_a(GRID.snow.cT_domain_ub) = GRID.snow.Snow_a(GRID.snow.cT_domain_ub) ...
            - ( SEB.Qe.*timestep.*24.*3600./PARA.constants.L_sg./PARA.constants.rho_i./nonAirFractionUppermostGridCell ...% - ( SEB.Qe.*timestep.*24.*3600./(L+L_lv)./1000./nonAirFractionUppermostGridCell ...
            -  SEB.Qe.*timestep.*24.*3600./PARA.constants.L_sg./PARA.constants.rho_i); %-  SEB.Qe.*timestep.*24.*3600./(L+L_lv)./1000);
        
        BALANCE.water.ds = BALANCE.water.ds - SEB.Qe.*timestep.*24.*3600./PARA.constants.L_sg./PARA.constants.rho_i*1000; % sublimation in [mm]
        if sum(isnan(GRID.snow.Snow_a(:)))>0
            fprintf('NaN in GRID.snow.Snow_a - CGS flag2\n')
        end
    end
    
    if sum(isnan(GRID.snow.Snow_a(:)))>0
        fprintf('NaN in GRID.snow.Snow_a - CGS flag3\n')
    end
    
    %---------- melt and infiltration -------------------------------------
    if max(T(GRID.snow.cT_domain))>0 || FORCING.i.rainfall>0 || sum(GRID.snow.Snow_w)>0  %cases when melt or infiltration occur
        
        [T(GRID.snow.cT_domain),...
            GRID.snow.Snow_i(GRID.snow.cT_domain),...
            GRID.snow.Snow_w(GRID.snow.cT_domain),...
            GRID.snow.Snow_a(GRID.snow.cT_domain),...
            newMelt] = ...
            snowMelt(T(GRID.snow.cT_domain),...
            GRID.snow.Snow_i(GRID.snow.cT_domain),...
            GRID.snow.Snow_w(GRID.snow.cT_domain),...
            GRID.snow.Snow_a(GRID.snow.cT_domain),...
            FORCING.i.rainfall.*timestep./1000,...
            c_temp(GRID.snow.cT_domain),...
            PARA);
        if sum(isnan(GRID.snow.Snow_i(:)))>0
            fprintf('NaN in GRID.snow.Snow_i - CGS flag2\n')
        end
        
        if sum(isnan(GRID.snow.Snow_a(:)))>0
            fprintf('NaN in GRID.snow.Snow_a - CGS flag4\n')
        end
        GRID.soil.water2pool = GRID.soil.water2pool + newMelt;
        BALANCE.water.dr_snowmelt = BALANCE.water.dr_snowmelt + (-newMelt.*1000);    % in [mm]
    end
    
    %-------- add the new snow to the upper most snow cell in the case of a exisiting snow cover -------------------
    if isempty( PARA.location.absolute_maxSnow_altitude )
        deltaSnow_i = max(0, FORCING.i.snowfall.*timestep./1000);
    else
        snowHeight = abs( GRID.general.K_grid(GRID.snow.cT_domain_ub) - GRID.general.K_grid(GRID.snow.cT_domain_lb+1) );
        maxSnowHeight = PARA.location.absolute_maxSnow_altitude - getAltitude( PARA, GRID );
        deltaSnow_i = max( [ 0, ...
            min( [ FORCING.i.snowfall.*timestep./1000, ...
            (maxSnowHeight - snowHeight ) .* PARA.snow.rho_snow ./ PARA.constants.rho_w ] ) ] ); %ensures that no more than maxSnow can accumulate
        %account for excess snow in water balance
        BALANCE.water.dr_excessSnow = BALANCE.water.dr_excessSnow -( FORCING.i.snowfall.*timestep - deltaSnow_i*1000 ); %defined as negative when snow is removed
    end
    
    GRID.snow.Snow_i(GRID.snow.cT_domain_ub) = GRID.snow.Snow_i(GRID.snow.cT_domain_ub) ...
        + deltaSnow_i;
    if sum(isnan(GRID.snow.Snow_i(:)))>0
        fprintf('NaN in GRID.snow.Snow_i - CGS flag3\n')
    end
    if sum(isnan(GRID.snow.Snow_a(:)))>0
        fprintf('NaN in GRID.snow.Snow_a - CGS flag5\n')
    end
    GRID.snow.Snow_a(GRID.snow.cT_domain_ub) = GRID.snow.Snow_a(GRID.snow.cT_domain_ub) ...
        + ( deltaSnow_i./(PARA.snow.rho_snow./ PARA.constants.rho_w) - deltaSnow_i);
    if sum(isnan(GRID.snow.Snow_a(:)))>0
        fprintf('NaN in GRID.snow.Snow_a - CGS flag6\n')
    end
    
else %no snow cover
    
    %---------- add the new snow into initial SWE variable in case of no snow cover------------------
    
    GRID.snow.SWEinitial = GRID.snow.SWEinitial + FORCING.i.snowfall.*timestep./1000 - GRID.snow.SWEinitial.*0.1.*timestep;
    GRID.soil.water2pool = GRID.soil.water2pool + GRID.snow.SWEinitial.*0.1.*timestep;
    BALANCE.water.dr_snowmelt = BALANCE.water.dr_snowmelt - GRID.snow.SWEinitial.*0.1.*timestep*1000; %SWEinitial decreasing counted as surface runoff
    
    %----- add the rainfall as runoff in case of no infiltration into frozen ground
    if ~PARA.modules.infiltration || (PARA.modules.infiltration && T(GRID.soil.cT_domain_ub)<=0 )%no infiltration scheme or uppermost soil cell frozen
        GRID.soil.water2pool = GRID.soil.water2pool + FORCING.i.rainfall.*timestep./1000;
        BALANCE.water.dr_rain = BALANCE.water.dr_rain - FORCING.i.rainfall.*timestep;
    end
    
end

%--------- update albedo after fresh fallen snow --------------------------
% determine time of last snowfall for albedo calculation
SEB.newSnow =  SEB.newSnow-SEB.newSnow.*0.1.*timestep + FORCING.i.snowfall.*timestep./1000;
if SEB.newSnow>= PARA.technical.SWEperCell/2
    PARA.snow.albedo=PARA.snow.max_albedo;
    SEB.newSnow=0;
end

end