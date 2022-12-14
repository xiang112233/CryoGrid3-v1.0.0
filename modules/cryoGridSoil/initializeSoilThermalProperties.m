%---------------------------------------------------
% function initialize
% creates matrices for heat capacity and conductivity

function GRID = initializeSoilThermalProperties(GRID, PARA)

    cT_water = GRID.soil.cT_water;
    cT_mineral = GRID.soil.cT_mineral;
    cT_organic = GRID.soil.cT_organic;
    cT_soilType = GRID.soil.cT_soilType;
    K_water = GRID.soil.K_water;
    K_mineral = GRID.soil.K_mineral;
    K_organic = GRID.soil.K_organic;
    K_soilType = GRID.soil.K_soilType;
    arraySize = PARA.technical.arraySizeT;
    cT_grid = GRID.general.cT_grid(GRID.soil.cT_domain);
    kh_bedrock = PARA.soil.kh_bedrock;

    c_w = PARA.constants.c_w; %4.2*10^6; %[J/m�K]
    c_o = PARA.constants.c_o; %2.5*10^6; %[J/m�K]
    c_m = PARA.constants.c_m; %2*10^6; %[J/m�K]
    c_a = PARA.constants.c_a; %0.00125*10^6;%[J/m�K]
    c_i = PARA.constants.c_i; %1.9*10^6;%[J/m�K]

    %density of water
    rho_w = PARA.constants.rho_w; %1000; %[kg/m�]
    %latent heat of freezing
    L_si = PARA.constants.L_sl; %334000; % [J/kg]
    deltaT=0.001*ones(size(cT_grid,1),1);

    % modification to assume pure water for mixed air/water cells
    cT_water(cT_mineral+cT_organic<=1e-6)=1.;

    %------- capacity part ----------------------------------------------------
    waterMin=0;
    water=cT_water;
    mineral=cT_mineral;
    organic=cT_organic;
    a=cT_soilType;

    cT_thawed=zeros(size(a,1),1);

    ch=mineral*c_m+organic*c_o+waterMin.*c_w+(water-waterMin)*c_i;

    %preallocate variable
    c_h2o=ones(length(a),length(-30:0.01:-1));

    j=1;
    for i= -30:0.01:-1
        c_h2o(:,j)=L_si*rho_w*(freezeC(water, 1-mineral-organic, a, i+deltaT/2, PARA)-freezeC(water, 1-mineral-organic, a, i-deltaT/2, PARA))/deltaT(1,1) < 0.05.*ch;
        j=j+1;
    end

    %preallocate variables
    cT_frozen=-30+((sum(c_h2o')')-1).*0.01; 

    c_h2o=ones(length(a),length(1:arraySize-2)+1); 
    water_c=c_h2o;
    ch=c_h2o;

    water_c(:,1) = freezeC(water,1-mineral-organic, a, cT_frozen, PARA);
    ch(:,1)      = mineral * c_m + organic * c_o +  water_c(:,1) * (c_w-c_i) + water * c_i;
    %here the derivative of the freeze curve dwc / dt is computed
    c_h2o(:,1)   = L_si*rho_w* (freezeC(water, 1-mineral-organic, a, cT_frozen+deltaT/2, PARA)-freezeC(water, 1-mineral-organic, a, cT_frozen-deltaT/2, PARA))/deltaT(1,1);
    for i=1:arraySize-2
        water_c(:,i+1) = freezeC(water, 1-mineral-organic, a, cT_thawed+(cT_frozen-cT_thawed)*(arraySize-2-i)/(arraySize-2), PARA);
        ch(:,i+1)      = mineral*c_m+organic*c_o+freezeC(water, 1-mineral-organic, a, cT_thawed+(cT_frozen-cT_thawed)*(arraySize-2-i)/(arraySize-2), PARA)*(c_w-c_i)+water*c_i;
        c_h2o(:,i+1)   = L_si*rho_w*(freezeC(water, 1-mineral-organic, a, cT_thawed+(cT_frozen-cT_thawed)*(arraySize-2-i)/(arraySize-2)+deltaT/2, PARA)-freezeC(water, 1-mineral-organic, a, cT_thawed+(cT_frozen-cT_thawed)*(arraySize-2-i)/(arraySize-2)-deltaT/2, PARA))/deltaT(1,1);
    end

    capacity = ch + c_h2o;
    capacity =[capacity mineral*c_m+organic*c_o+water*c_w];  %capacity matrix for unfrozen soil

    liquidWaterContent = [water_c water]; % water content

    %---------- conductivity part ---------------------------------------------

    % changed to cT-grid since K- interpolation is done external now
    water=cT_water;
    mineral=cT_mineral;
    organic=cT_organic;
    a=cT_soilType;

    K_frozen=cT_frozen;
    K_thawed=cT_thawed;

    %preallocate variables
    water_c=ones(length(a),length(1:arraySize-2)+1);
    water_c(:,1)=freezeC(water, 1-mineral-organic, a, K_frozen, PARA);
    conductivity=water_c;

    for i=1:arraySize-2
        water_c(:,i+1)=freezeC(water, 1-mineral-organic, a, K_thawed+(K_frozen-K_thawed)*(arraySize-2-i)/(arraySize-2), PARA);
    end
    for i=1:size(a,1)
        ice_c=water(i,1)*ones(1,arraySize-1)-water_c(i,:);
        conductivity(i,:)=conductivity2(water_c(i,:), ice_c, mineral(i,1), organic(i,1), PARA);
    end

    conductivity=[conductivity conductivity(:,size(conductivity,2))]; %conductivity matrix for soil filled

    %----------- write lookup tables to GRID struct
    liquidWaterContent = real(liquidWaterContent);
    conductivity = real(conductivity);
    capacity = real(capacity);


    GRID.soil.cT_frozen = cT_frozen;
    GRID.soil.cT_thawed = cT_thawed;
    GRID.soil.K_frozen = K_frozen;
    GRID.soil.K_thawed = K_thawed;
    GRID.soil.conductivity = conductivity;
    GRID.soil.capacity = capacity;
    GRID.soil.liquidWaterContent = liquidWaterContent;
end

%---------------------------------------------------
% function freezeC
%part of the freezeCurve for T<T_th - for T>T_th, the value for water
%content is 'water' by default
function waterC =  freezeC(thetaTot, thetaSat, soilType, T, PARA)
    T=T+273.15;
    thetaTot=min(thetaSat, thetaTot); 
    thetaRes=zeros(size(soilType));
    alpha=zeros(size(soilType));
    n=zeros(size(soilType));

    %set conditions for soil types 
    thetaRes(soilType==1) = 0;
    alpha(soilType==1)    = 4;
    n(soilType==1)        = 2;

    thetaRes(soilType==2) = 0.05;
    alpha(soilType==2)    = 0.65;
    n(soilType==2)        = 1.7;

    m=1-1./n;
    waterPotZero=-1./alpha .*( ((thetaTot-thetaRes)./(thetaSat-thetaRes) ).^(-1./m) -1 ).^(1./n);
    Tstar = 273.15 + PARA.constants.g .* 273.15 ./ PARA.constants.L_sl .* waterPotZero;
    waterC=zeros(size(T));


    waterPot=zeros(size(T));

    waterC(T>=273.15) = thetaTot(T>=273.15);

    % C_eff has plateau from 0 to -0.05 °C
    waterPot(T<273.15 & T>273.1) = waterPotZero(T<273.15 & T>273.1)...
             + (3.34e5./9.81./Tstar(T<273.15 & T>273.1).*(273.1-Tstar(T<273.15 & T>273.1)))...
             .* (273.1<Tstar(T<273.15 & T>273.1));

    waterC(T<273.15 & T>273.1) = thetaRes(T<273.15 & T>273.1)...
                                 + (thetaSat(T<273.15 & T>273.1)-thetaRes(T<273.15 & T>273.1))...
                                 .*(1+(-alpha(T<273.15 & T>273.1).*waterPot(T<273.15 & T>273.1)).^n(T<273.15 & T>273.1)).^(-m(T<273.15 & T>273.1));

    waterC(T<273.15 & T>273.1) = waterC(T<273.15 & T>273.1) + (thetaTot(T<273.15 & T>273.1)-waterC(T<273.15 & T>273.1)) ./ 0.05 .* (T(T<273.15 & T>273.1)-273.1);


    waterPot(T<=273.1)= waterPotZero(T<=273.1)+(3.34e5./9.81./Tstar(T<=273.1).*(T(T<=273.1)-Tstar(T<=273.1))).*(T(T<=273.1)<Tstar(T<=273.1));
    waterC(T<=273.1)  = thetaRes(T<=273.1)+(thetaSat(T<=273.1)-thetaRes(T<=273.1)).*(1+(-alpha(T<=273.1).*waterPot(T<=273.1)).^n(T<=273.1)).^(-m(T<=273.1));
end
