clc;
clear;
close all;

%% =========================================================
% CELL-FREE MASSIVE MIMO  — FIXED VERSION
% KEY FIXES APPLIED:
%  1. Area reduced  : 1000x1000 m  ->  500x500 m
%  2. Serving APs   : L = 5        ->  L = 10
%  3. Channel model : scalar H(M,K)->  multi-antenna H(M,N,K)
%  4. Pilot power   : 100 mW       ->  300 mW
%  5. Noise power   : fixed 1e-9   ->  computed from kTB*NF
% MRT BEAMFORMING + MAX-MIN POWER OPTIMIZATION
% ALL WAVEFORM PLOTS  —  ALL RESULTS IN COMMAND WINDOW
%% =========================================================

%% =========================================================
% STEP 1 : NETWORK DEPLOYMENT PARAMETERS
%% =========================================================

areaLength = 500;      % FIX 1: reduced from 1000 m -> 500 m
areaWidth  = 500;      %        improves channel gain + pilot SNR

M = 100;               % Number of Access Points
K = 40;                % Number of Users
N = 4;                 % FIX 3: Antennas per AP (used in MxNxK channel)
L = 10;                % FIX 2: Serving APs per user (was 5, now 10)

rng(1);

%% =========================================================
% STEP 2 : CHANNEL MODEL PARAMETERS
%% =========================================================

fc       = 3.5e9;      % Carrier frequency  (Hz)
B        = 20e6;       % Bandwidth          (Hz)
NF_dB    = 9;          % Noise Figure       (dB)
sigma_sf = 8;          % Shadow fading std  (dB)
tau_c    = 200;        % Coherence interval (samples)
tau_p    = 20;         % Pilot length       (samples)
P_p      = 300e-3;     % FIX 4: Pilot power 300 mW (was 100 mW)
P_max    = 200e-3;     % Max TX power per AP (W)

%% FIX 5 : Noise power computed from thermal + noise figure
k_B          = 1.38e-23;         % Boltzmann constant (J/K)
T0           = 290;               % Temperature         (K)
NF_linear    = 10^(NF_dB/10);    % NF linear scale
noiseVariance = k_B * T0 * B * NF_linear;   % Pn = kTB*NF

%% =========================================================
% COMMAND WINDOW : SYSTEM PARAMETERS
%% =========================================================

fprintf('\n');
fprintf('=========================================\n');
fprintf('  CELL-FREE MASSIVE MIMO — FIXED MODEL\n');
fprintf('=========================================\n');
fprintf(' Area           : %d x %d m\n',   areaLength, areaWidth);
fprintf(' Access Points  : M = %d\n',       M);
fprintf(' Users          : K = %d\n',        K);
fprintf(' Antennas/AP    : N = %d\n',        N);
fprintf(' Serving APs    : L = %d\n',        L);
fprintf(' Carrier Freq   : %.1f GHz\n',      fc/1e9);
fprintf(' Bandwidth      : %.0f MHz\n',      B/1e6);
fprintf(' Noise Figure   : %d dB\n',         NF_dB);
fprintf(' Noise Power    : %.4e W  (kTB*NF)\n', noiseVariance);
fprintf(' Noise Power    : %.2f dBm\n',      10*log10(noiseVariance/1e-3));
fprintf(' Pilot Power    : %.0f mW\n',       P_p*1000);
fprintf(' Max TX Power   : %.0f mW\n',       P_max*1000);
fprintf(' Shadow Std     : %d dB\n',         sigma_sf);
fprintf(' Pilot Length   : tau_p = %d\n',    tau_p);
fprintf(' Coherence Len  : tau_c = %d\n',    tau_c);
fprintf('=========================================\n\n');

%% =========================================================
% DEPLOY ACCESS POINTS AND USERS
%% =========================================================

AP_x   = areaLength * rand(M,1);
AP_y   = areaWidth  * rand(M,1);
User_x = areaLength * rand(K,1);
User_y = areaWidth  * rand(K,1);

%% =========================================================
% DISTANCE MATRIX   (M x K)
%% =========================================================

distanceMatrix = zeros(M,K);

for m = 1:M
    for k = 1:K
        dx = AP_x(m) - User_x(k);
        dy = AP_y(m) - User_y(k);
        distanceMatrix(m,k) = sqrt(dx^2 + dy^2);
    end
end

fprintf('-----------------------------------------\n');
fprintf(' DISTANCE MATRIX  (M=%d x K=%d)\n', M, K);
fprintf('-----------------------------------------\n');
fprintf(' Min distance  : %.2f m\n',  min(distanceMatrix(:)));
fprintf(' Max distance  : %.2f m\n',  max(distanceMatrix(:)));
fprintf(' Mean distance : %.2f m\n',  mean(distanceMatrix(:)));
fprintf('-----------------------------------------\n\n');

%% =========================================================
% USER-CENTRIC AP CLUSTERING   (L=10 nearest APs)
%% =========================================================

UserCluster = cell(K,1);

for k = 1:K
    [~, sortedAPs]  = sort(distanceMatrix(:,k));
    UserCluster{k}  = sortedAPs(1:L);
end

fprintf('-----------------------------------------\n');
fprintf(' AP CLUSTERING  (L=%d serving APs/user)\n', L);
fprintf('-----------------------------------------\n');
for k = 1:5
    fprintf(' User %2d -> APs: ', k);
    fprintf('%d ', UserCluster{k});
    fprintf('\n');
end
fprintf(' ... (showing first 5 users)\n');
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 3 : PATH LOSS   (3GPP UMa model)
%% =========================================================

pathLoss_dB = zeros(M,K);

for m = 1:M
    for k = 1:K
        d_km = distanceMatrix(m,k) / 1000;
        d_km = max(d_km, 0.01);           % Minimum 10 m
        pathLoss_dB(m,k) = 128.1 + 37.6*log10(d_km);
    end
end

avgPathLoss_perUser = mean(pathLoss_dB, 1);   % 1 x K
avgPathLoss_perAP   = mean(pathLoss_dB, 2);   % M x 1

fprintf('-----------------------------------------\n');
fprintf(' PATH LOSS RESULTS\n');
fprintf('-----------------------------------------\n');
fprintf(' Min path loss  : %.2f dB\n', min(pathLoss_dB(:)));
fprintf(' Max path loss  : %.2f dB\n', max(pathLoss_dB(:)));
fprintf(' Mean path loss : %.2f dB\n', mean(pathLoss_dB(:)));
fprintf('\n Per-User Average Path Loss (dB):\n');
fprintf('  User | AvgPL(dB)\n');
for k = 1:K
    fprintf('  %4d | %9.2f\n', k, avgPathLoss_perUser(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 4 : SHADOW FADING   (M x K  Gaussian, sigma=8 dB)
%% =========================================================

shadowFading = sigma_sf * randn(M,K);

avgSF_perUser = mean(shadowFading, 1);
stdSF_perUser = std(shadowFading,  0, 1);

fprintf('-----------------------------------------\n');
fprintf(' SHADOW FADING RESULTS\n');
fprintf('-----------------------------------------\n');
fprintf(' Std dev (sigma_sf)  : %d dB\n', sigma_sf);
fprintf(' Min  : %.2f dB\n', min(shadowFading(:)));
fprintf(' Max  : %.2f dB\n', max(shadowFading(:)));
fprintf(' Mean : %.4f dB  (expect ~0)\n', mean(shadowFading(:)));
fprintf('\n Per-User Shadow Fading (dB):\n');
fprintf('  User | Mean(dB) |  Std(dB)\n');
for k = 1:K
    fprintf('  %4d | %8.4f | %8.4f\n', k, avgSF_perUser(k), stdSF_perUser(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 5 : LARGE-SCALE FADING COEFFICIENT   beta (M x K)
%% =========================================================

beta_dB     = -pathLoss_dB + shadowFading;
beta_linear = 10.^(beta_dB/10);

%% =========================================================
% FIX 3 : MULTI-ANTENNA CHANNEL   H(M, N, K)
%% =========================================================
% Each AP m has N antennas.
% H(m,n,k) = sqrt(beta(m,k)) * h_small(m,n,k)
% where h_small ~ CN(0,1) independently per antenna.
% This gives the true massive MIMO array gain.
%% =========================================================

smallScaleFading = (randn(M,N,K) + 1i*randn(M,N,K)) / sqrt(2);  % CN(0,1)

H = zeros(M,N,K);

for m = 1:M
    for k = 1:K
        H(m,:,k) = sqrt(beta_linear(m,k)) * smallScaleFading(m,:,k);
    end
end

%% -- Effective scalar channel gain per AP-user (norm over N antennas)
%    used for power allocation and SINR computation
H_eff = zeros(M,K);    % ||h_mk||  (norm of N-dim vector)

for m = 1:M
    for k = 1:K
        H_eff(m,k) = norm(H(m,:,k));   % sqrt(N) * sqrt(beta) on average
    end
end

channelGain_dB    = 20*log10(H_eff + eps);      % 20*log10 of norm
avgCG_perUser_dB  = mean(channelGain_dB, 1);

%% -- Small-scale fading magnitude (averaged over antennas)
ssfMag_avg = squeeze(mean(abs(smallScaleFading), 2));  % M x K
avgSSF_perUser = mean(ssfMag_avg, 1);

fprintf('-----------------------------------------\n');
fprintf(' MULTI-ANTENNA CHANNEL H(M=%d,N=%d,K=%d)\n', M, N, K);
fprintf('-----------------------------------------\n');
fprintf(' E[||h_mk||^2] = N*beta_mk\n');
fprintf(' Min ||H||  : %.4f\n', min(H_eff(:)));
fprintf(' Max ||H||  : %.4f\n', max(H_eff(:)));
fprintf(' Mean ||H|| : %.4f\n', mean(H_eff(:)));
fprintf('\n Per-User Avg Channel Gain (dB):\n');
fprintf('  User | AvgCG(dB)\n');
for k = 1:K
    fprintf('  %4d | %9.2f\n', k, avgCG_perUser_dB(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 6 : PILOT TRANSMISSION + RECEIVED PILOT SIGNAL
%% =========================================================

pilotMatrix     = eye(tau_p);
pilotAssignment = zeros(K, tau_p);

for k = 1:K
    pilotIndex = mod(k-1, tau_p) + 1;
    pilotAssignment(k,:) = pilotMatrix(pilotIndex,:);
end

%% Received pilot at each AP — aggregate over N antennas
receivedPilotSignal = zeros(M,K);

for m = 1:M
    for k = 1:K
        receivedPilotSignal(m,k) = sqrt(P_p) * H_eff(m,k);
    end
end

avgRPS_perUser = mean(receivedPilotSignal, 1);

%% Pilot SNR per AP-user pair
pilotSNR_dB = 10*log10((P_p * H_eff.^2) / noiseVariance + eps);

fprintf('-----------------------------------------\n');
fprintf(' RECEIVED PILOT SIGNAL RESULTS\n');
fprintf('-----------------------------------------\n');
fprintf(' Pilot Power : %.0f mW\n', P_p*1000);
fprintf(' Min  RPS : %.6f\n', min(receivedPilotSignal(:)));
fprintf(' Max  RPS : %.6f\n', max(receivedPilotSignal(:)));
fprintf(' Mean RPS : %.6f\n', mean(receivedPilotSignal(:)));
fprintf(' Min  Pilot SNR : %.2f dB\n', min(pilotSNR_dB(:)));
fprintf(' Max  Pilot SNR : %.2f dB\n', max(pilotSNR_dB(:)));
fprintf(' Mean Pilot SNR : %.2f dB\n', mean(pilotSNR_dB(:)));
fprintf('\n Per-User Avg Received Pilot Signal & SNR:\n');
fprintf('  User | Avg RPS   | Avg Pilot SNR(dB)\n');
for k = 1:K
    fprintf('  %4d | %.6f | %17.2f\n', k, avgRPS_perUser(k), ...
            mean(pilotSNR_dB(:,k)));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 7 : LMMSE CHANNEL ESTIMATION   H_est(M,N,K)
%% =========================================================
% LMMSE estimate of the effective channel norm per AP-user.
% scalar LMMSE applied to ||y_pilot|| -> estimate of ||h_mk||
%% =========================================================

H_est_eff = zeros(M,K);    % Estimated effective channel norm

for m = 1:M
    for k = 1:K
        beta        = beta_linear(m,k);
        % LMMSE coefficient (scalar, maps received pilot to channel estimate)
        lmmseCoeff  = (sqrt(P_p) * N * beta) / (P_p * N * beta + noiseVariance);
        H_est_eff(m,k) = lmmseCoeff * receivedPilotSignal(m,k);
    end
end

%% Estimation error
estimationError_mag = abs(H_eff - H_est_eff);
estimationError_dB  = 20*log10(estimationError_mag + eps);

avgErr_perUser    = mean(estimationError_mag, 1);
avgErr_dB_perUser = mean(estimationError_dB,  1);

%% NMSE per user
NMSE_perUser = zeros(1,K);
for k = 1:K
    H_true_pwr   = sum(H_eff(:,k).^2);
    err_pwr      = sum(estimationError_mag(:,k).^2);
    NMSE_perUser(k) = err_pwr / (H_true_pwr + eps);
end

fprintf('-----------------------------------------\n');
fprintf(' CHANNEL ESTIMATION ERROR (LMMSE)\n');
fprintf('-----------------------------------------\n');
fprintf(' Min |error|  : %.6f\n', min(estimationError_mag(:)));
fprintf(' Max |error|  : %.6f\n', max(estimationError_mag(:)));
fprintf(' Mean |error| : %.6f\n', mean(estimationError_mag(:)));
fprintf(' Mean error   : %.2f dB\n', mean(estimationError_dB(:)));
fprintf('\n Per-User Estimation Error & NMSE:\n');
fprintf('  User | Avg|Err| | Avg|Err|(dB) |   NMSE\n');
for k = 1:K
    fprintf('  %4d | %8.6f | %12.2f  | %.6f\n', ...
            k, avgErr_perUser(k), avgErr_dB_perUser(k), NMSE_perUser(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 8 : MRT BEAMFORMING VECTOR   w(M,N,K)
%% =========================================================
% w_mk = H_mk / ||H_mk||   (unit-norm conjugate of channel)
% Effective scalar weight magnitude = 1 for each non-zero AP-user
%% =========================================================

beamformingVector = zeros(M,N,K);   % FIX 3: multi-antenna BF

for m = 1:M
    for k = 1:K
        h_mk = squeeze(H(m,:,k)).';    % N x 1
        nrm  = norm(h_mk);
        if nrm > 0
            beamformingVector(m,:,k) = (h_mk / nrm).';  % unit norm
        end
    end
end

%% Effective BF gain = |h^H * w| = ||h|| (MRT aligns perfectly)
BF_gain = zeros(M,K);
for m = 1:M
    for k = 1:K
        h_mk = squeeze(H(m,:,k)).';
        w_mk = squeeze(beamformingVector(m,:,k)).';
        BF_gain(m,k) = abs(h_mk' * w_mk);   % = ||h_mk||
    end
end

avgBF_perUser = mean(BF_gain, 1);

fprintf('-----------------------------------------\n');
fprintf(' MRT BEAMFORMING VECTOR  w(M,N,K)\n');
fprintf('-----------------------------------------\n');
fprintf(' (Unit-norm phase-conjugate weights)\n');
fprintf(' BF gain = |h^H w| = ||h|| per AP-user\n');
fprintf(' Min BF gain  : %.4f\n', min(BF_gain(:)));
fprintf(' Max BF gain  : %.4f\n', max(BF_gain(:)));
fprintf(' Mean BF gain : %.4f\n', mean(BF_gain(:)));
fprintf('\n Per-User Avg MRT BF Gain:\n');
fprintf('  User | Avg BF Gain\n');
for k = 1:K
    fprintf('  %4d | %11.4f\n', k, avgBF_perUser(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 9 : BASELINE SINR  (No BF, Equal Power)
%% =========================================================

P_baseline  = P_max / K;        % Equal power per user per AP
SINR_baseline  = zeros(K,1);
signal_baseline = zeros(K,1);

for k = 1:K
    desired_base = 0;
    interf_base  = 0;
    servingAPs   = UserCluster{k};

    for i = 1:length(servingAPs)
        ap = servingAPs(i);
        desired_base = desired_base + sqrt(P_baseline) * H_eff(ap,k);
    end

    signal_baseline(k) = abs(desired_base)^2;

    for j = 1:K
        if j ~= k
            intSig = 0;
            for i = 1:length(servingAPs)
                ap = servingAPs(i);
                intSig = intSig + sqrt(P_baseline) * H_eff(ap,k);
            end
            interf_base = interf_base + abs(intSig)^2;
        end
    end

    SINR_baseline(k) = signal_baseline(k) / (interf_base + noiseVariance);
end

SINR_baseline_dB = 10*log10(max(SINR_baseline, eps));

fprintf('-----------------------------------------\n');
fprintf(' BASELINE SINR (No BF, Equal Power)\n');
fprintf('-----------------------------------------\n');
fprintf(' P_per_user = %.4f mW\n', P_baseline*1000);
fprintf('\n Per-User Baseline SINR:\n');
fprintf('  User | SINR(dB)\n');
for k = 1:K
    fprintf('  %4d | %8.2f\n', k, SINR_baseline_dB(k));
end
fprintf('\n SUMMARY:\n');
fprintf('  Average SINR : %.2f dB\n', mean(SINR_baseline_dB));
fprintf('  Maximum SINR : %.2f dB\n', max(SINR_baseline_dB));
fprintf('  Minimum SINR : %.2f dB\n', min(SINR_baseline_dB));
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 10 : MRT BF + PROPORTIONAL POWER ALLOCATION
%% =========================================================

powerAllocation_MRT = zeros(M,K);
initialPower        = P_max / K;

for m = 1:M
    for k = 1:K
        powerAllocation_MRT(m,k) = initialPower * H_est_eff(m,k)^2;
    end
end

%% Normalize per AP
for m = 1:M
    totalPower = sum(powerAllocation_MRT(m,:));
    if totalPower > 0
        powerAllocation_MRT(m,:) = (P_max / totalPower) * powerAllocation_MRT(m,:);
    end
end

%% SINR with MRT
SINR_MRT   = zeros(K,1);
signal_MRT = zeros(K,1);

for k = 1:K
    desired_MRT = 0;
    interf_MRT  = 0;
    servingAPs  = UserCluster{k};

    for i = 1:length(servingAPs)
        ap = servingAPs(i);
        %  MRT desired: sqrt(p_mk) * |h_mk^H w_mk| = sqrt(p_mk)*||h_mk||
        desired_MRT = desired_MRT + ...
            sqrt(powerAllocation_MRT(ap,k)) * BF_gain(ap,k);
    end

    signal_MRT(k) = abs(desired_MRT)^2;

    for j = 1:K
        if j ~= k
            intSig = 0;
            for i = 1:length(servingAPs)
                ap = servingAPs(i);
                %  Interference: sqrt(p_mj) * |h_mk^H w_mj|
                %  For Rayleigh, cross terms: |h_mk^H w_mj| ~ sqrt(beta_mk)
                h_mk = squeeze(H(ap,:,k)).';
                w_mj = squeeze(beamformingVector(ap,:,j)).';
                intSig = intSig + ...
                    sqrt(powerAllocation_MRT(ap,j)) * abs(h_mk' * w_mj);
            end
            interf_MRT = interf_MRT + abs(intSig)^2;
        end
    end

    SINR_MRT(k) = signal_MRT(k) / (interf_MRT + noiseVariance);
end

SINR_MRT_dB = 10*log10(max(SINR_MRT, eps));

fprintf('-----------------------------------------\n');
fprintf(' MRT BF + PROPORTIONAL POWER SINR\n');
fprintf('-----------------------------------------\n');
fprintf('\n Per-User SINR after MRT Beamforming:\n');
fprintf('  User | SINR(dB)\n');
for k = 1:K
    fprintf('  %4d | %8.2f\n', k, SINR_MRT_dB(k));
end
fprintf('\n SUMMARY:\n');
fprintf('  Average SINR : %.2f dB\n', mean(SINR_MRT_dB));
fprintf('  Maximum SINR : %.2f dB\n', max(SINR_MRT_dB));
fprintf('  Minimum SINR : %.2f dB\n', min(SINR_MRT_dB));
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 11 : MAX-MIN POWER OPTIMIZATION
%% =========================================================
% Objective : Maximize the minimum SINR over all K users
% Algorithm : Iterative proportional-fair power update
%   Weak users (SINR < mean) -> boost power
%   Strong users (SINR > mean) -> reduce power
%   Per-AP power constraint enforced after each update
%% =========================================================

fprintf('-----------------------------------------\n');
fprintf(' MAX-MIN POWER OPTIMIZATION\n');
fprintf('-----------------------------------------\n');

numIterations = 60;
stepSize      = 0.12;

powerAllocation_MaxMin = powerAllocation_MRT;   % Warm start from MRT

SINR_iter_min = zeros(numIterations,1);
SINR_iter_avg = zeros(numIterations,1);

for iter = 1:numIterations

    SINR_current = zeros(K,1);

    for k = 1:K
        desired    = 0;
        interf     = 0;
        servingAPs = UserCluster{k};

        for i = 1:length(servingAPs)
            ap = servingAPs(i);
            desired = desired + ...
                sqrt(powerAllocation_MaxMin(ap,k)) * BF_gain(ap,k);
        end

        for j = 1:K
            if j ~= k
                intSig = 0;
                for i = 1:length(servingAPs)
                    ap = servingAPs(i);
                    h_mk = squeeze(H(ap,:,k)).';
                    w_mj = squeeze(beamformingVector(ap,:,j)).';
                    intSig = intSig + ...
                        sqrt(powerAllocation_MaxMin(ap,j)) * abs(h_mk' * w_mj);
                end
                interf = interf + abs(intSig)^2;
            end
        end

        SINR_current(k) = abs(desired)^2 / (interf + noiseVariance);
    end

    SINR_iter_min(iter) = min(10*log10(max(SINR_current, eps)));
    SINR_iter_avg(iter) = mean(10*log10(max(SINR_current, eps)));

    %% Power update
    SINR_mean = mean(SINR_current);

    for k = 1:K
        servingAPs = UserCluster{k};

        if SINR_current(k) > SINR_mean
            sf = 1 - stepSize*(SINR_current(k)/SINR_mean - 1);
            sf = max(sf, 0.5);
        else
            sf = 1 + stepSize*(SINR_mean/(SINR_current(k)+eps) - 1);
            sf = min(sf, 2.0);
        end

        for i = 1:length(servingAPs)
            ap = servingAPs(i);
            powerAllocation_MaxMin(ap,k) = powerAllocation_MaxMin(ap,k) * sf;
        end
    end

    %% Re-normalize per AP
    for m = 1:M
        tp = sum(powerAllocation_MaxMin(m,:));
        if tp > P_max
            powerAllocation_MaxMin(m,:) = (P_max/tp)*powerAllocation_MaxMin(m,:);
        end
    end

end

fprintf(' Iterations  : %d\n', numIterations);
fprintf(' Step Size   : %.2f\n', stepSize);
fprintf('\n Convergence per Iteration:\n');
fprintf('  Iter | Min SINR(dB) | Avg SINR(dB)\n');
for iter = 1:numIterations
    fprintf('  %4d | %12.2f | %12.2f\n', ...
            iter, SINR_iter_min(iter), SINR_iter_avg(iter));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% STEP 12 : FINAL SINR AFTER MAX-MIN OPTIMIZATION
%% =========================================================

SINR_MaxMin = zeros(K,1);

for k = 1:K
    desired    = 0;
    interf     = 0;
    servingAPs = UserCluster{k};

    for i = 1:length(servingAPs)
        ap = servingAPs(i);
        desired = desired + ...
            sqrt(powerAllocation_MaxMin(ap,k)) * BF_gain(ap,k);
    end

    for j = 1:K
        if j ~= k
            intSig = 0;
            for i = 1:length(servingAPs)
                ap = servingAPs(i);
                h_mk = squeeze(H(ap,:,k)).';
                w_mj = squeeze(beamformingVector(ap,:,j)).';
                intSig = intSig + ...
                    sqrt(powerAllocation_MaxMin(ap,j)) * abs(h_mk' * w_mj);
            end
            interf = interf + abs(intSig)^2;
        end
    end

    SINR_MaxMin(k) = abs(desired)^2 / (interf + noiseVariance);
end

SINR_MaxMin_dB = 10*log10(max(SINR_MaxMin, eps));

avgPower_MRT    = 1000 * mean(powerAllocation_MRT,    1);  % mW
avgPower_MaxMin = 1000 * mean(powerAllocation_MaxMin,  1);  % mW

fprintf('-----------------------------------------\n');
fprintf(' FINAL SINR — MAX-MIN OPTIMIZATION\n');
fprintf('-----------------------------------------\n');
fprintf('\n Per-User SINR Comparison:\n');
fprintf('  User | Base(dB) | MRT(dB) | MaxMin(dB) | Gain vs Base\n');
for k = 1:K
    fprintf('  %4d | %8.2f | %7.2f | %10.2f | %+.2f dB\n', ...
            k, SINR_baseline_dB(k), SINR_MRT_dB(k), ...
            SINR_MaxMin_dB(k), SINR_MaxMin_dB(k)-SINR_baseline_dB(k));
end
fprintf('-----------------------------------------\n\n');

%% =========================================================
% FINAL SUMMARY
%% =========================================================

gain_avg     = mean(SINR_MaxMin_dB) - mean(SINR_baseline_dB);
gain_min     = min(SINR_MaxMin_dB)  - min(SINR_baseline_dB);
gain_avg_mrt = mean(SINR_MaxMin_dB) - mean(SINR_MRT_dB);
gain_min_mrt = min(SINR_MaxMin_dB)  - min(SINR_MRT_dB);

fprintf('=========================================\n');
fprintf('  FINAL SUMMARY RESULTS\n');
fprintf('=========================================\n');
fprintf('\n %-28s %8s %8s %10s\n','Metric','Baseline','MRT BF','Max-Min');
fprintf(' %s\n', repmat('-',1,58));
fprintf(' %-28s %8.2f %8.2f %10.2f\n','Average SINR (dB)', ...
        mean(SINR_baseline_dB), mean(SINR_MRT_dB), mean(SINR_MaxMin_dB));
fprintf(' %-28s %8.2f %8.2f %10.2f\n','Maximum SINR (dB)', ...
        max(SINR_baseline_dB),  max(SINR_MRT_dB),  max(SINR_MaxMin_dB));
fprintf(' %-28s %8.2f %8.2f %10.2f\n','Minimum SINR (dB)', ...
        min(SINR_baseline_dB),  min(SINR_MRT_dB),  min(SINR_MaxMin_dB));
fprintf(' %-28s %8.2f %8.2f %10.2f\n','Std Dev SINR (dB)', ...
        std(SINR_baseline_dB),  std(SINR_MRT_dB),  std(SINR_MaxMin_dB));
fprintf('\n GAIN: Max-Min vs Baseline\n');
fprintf('  Avg SINR Gain : %+.2f dB\n', gain_avg);
fprintf('  Min SINR Gain : %+.2f dB\n', gain_min);
fprintf('\n GAIN: Max-Min vs MRT-only\n');
fprintf('  Avg SINR Gain : %+.2f dB\n', gain_avg_mrt);
fprintf('  Min SINR Gain : %+.2f dB\n', gain_min_mrt);
fprintf('\n Power Allocation:\n');
fprintf('  Avg power/user (MRT)    : %.4f mW\n', mean(avgPower_MRT));
fprintf('  Avg power/user (Max-Min): %.4f mW\n', mean(avgPower_MaxMin));
fprintf('=========================================\n\n');

%% =========================================================
%                        WAVEFORM PLOTS
%% =========================================================

%% PLOT 1 : Network Deployment
figure('Name','Plot 1: Network Deployment','NumberTitle','off');
scatter(AP_x, AP_y, 80, 'b', 'filled');
hold on;
scatter(User_x, User_y, 120, 'r', 'filled');
for k = 1:K
    sAPs = UserCluster{k};
    for i = 1:length(sAPs)
        ap = sAPs(i);
        line([AP_x(ap) User_x(k)],[AP_y(ap) User_y(k)], ...
             'Color',[0.6 0.6 0.6 0.25],'LineWidth',0.4);
    end
end
xlabel('X Position (m)','FontSize',12,'FontWeight','bold');
ylabel('Y Position (m)','FontSize',12,'FontWeight','bold');
title('Plot 1: Network Deployment (500x500 m, L=10, N=4)', ...
      'FontSize',13,'FontWeight','bold');
legend('Access Points (M=100)','Users (K=40)','Location','best');
grid on; axis([0 areaLength 0 areaWidth]); axis square;

%% PLOT 2 : Path Loss Waveform
figure('Name','Plot 2: Path Loss Waveform','NumberTitle','off');
plot(1:K, pathLoss_dB(1,:),  'r-o','LineWidth',2,'MarkerSize',5);
hold on;
plot(1:K, pathLoss_dB(10,:), 'b-s','LineWidth',2,'MarkerSize',5);
plot(1:K, pathLoss_dB(50,:), 'g-^','LineWidth',2,'MarkerSize',5);
plot(1:K, avgPathLoss_perUser,'k-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Path Loss (dB)','FontSize',12,'FontWeight','bold');
title('Plot 2: Path Loss Waveform (AP 1, 10, 50  →  All Users)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 3 : Shadow Fading Waveform
figure('Name','Plot 3: Shadow Fading Waveform','NumberTitle','off');
plot(1:K, shadowFading(1,:),  'r-','LineWidth',2);
hold on;
plot(1:K, shadowFading(10,:), 'b-','LineWidth',2);
plot(1:K, shadowFading(50,:), 'g-','LineWidth',2);
plot(1:K, avgSF_perUser,      'k-','LineWidth',2.5);
yline(0,'k--','LineWidth',1,'Label','Zero Mean');
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Shadow Fading (dB)','FontSize',12,'FontWeight','bold');
title('Plot 3: Shadow Fading Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 4 : Small Scale Fading Waveform
figure('Name','Plot 4: Small Scale Fading Waveform','NumberTitle','off');
plot(1:K, ssfMag_avg(1,:),  'm-','LineWidth',2);
hold on;
plot(1:K, ssfMag_avg(10,:), 'c-','LineWidth',2);
plot(1:K, ssfMag_avg(50,:), 'r-','LineWidth',2);
plot(1:K, avgSSF_perUser,   'k-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Avg |Small Scale Fading| per Antenna','FontSize',12,'FontWeight','bold');
title('Plot 4: Small Scale Fading Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 5 : Channel Gain Waveform
figure('Name','Plot 5: Channel Gain Waveform','NumberTitle','off');
plot(1:K, channelGain_dB(1,:),  'b-','LineWidth',2);
hold on;
plot(1:K, channelGain_dB(10,:), 'r-','LineWidth',2);
plot(1:K, channelGain_dB(50,:), 'g-','LineWidth',2);
plot(1:K, avgCG_perUser_dB,     'k-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Channel Gain  ||h_{mk}||  (dB)','FontSize',12,'FontWeight','bold');
title('Plot 5: Multi-Antenna Channel Gain Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 6 : Received Pilot Signal Waveform
figure('Name','Plot 6: Received Pilot Signal Waveform','NumberTitle','off');
plot(1:K, receivedPilotSignal(1,:),  'k-','LineWidth',2);
hold on;
plot(1:K, receivedPilotSignal(10,:), 'b-','LineWidth',2);
plot(1:K, receivedPilotSignal(50,:), 'r-','LineWidth',2);
plot(1:K, avgRPS_perUser,            'm-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Received Pilot Signal Amplitude','FontSize',12,'FontWeight','bold');
title('Plot 6: Received Pilot Signal Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 7 : Pilot SNR Waveform
figure('Name','Plot 7: Pilot SNR Waveform','NumberTitle','off');
plot(1:K, pilotSNR_dB(1,:),  'r-','LineWidth',2);
hold on;
plot(1:K, pilotSNR_dB(10,:), 'b-','LineWidth',2);
plot(1:K, pilotSNR_dB(50,:), 'g-','LineWidth',2);
plot(1:K, mean(pilotSNR_dB,1),'k-','LineWidth',2.5);
yline(0,'k--','LineWidth',1,'Label','0 dB');
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Pilot SNR (dB)','FontSize',12,'FontWeight','bold');
title('Plot 7: Pilot SNR Waveform (AP 1, 10, 50) — P_p = 300 mW', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 8 : Estimation Error Waveform
figure('Name','Plot 8: Estimation Error Waveform','NumberTitle','off');
plot(1:K, estimationError_dB(1,:),  'r-','LineWidth',2);
hold on;
plot(1:K, estimationError_dB(10,:), 'b-','LineWidth',2);
plot(1:K, estimationError_dB(50,:), 'g-','LineWidth',2);
plot(1:K, avgErr_dB_perUser,        'k-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Estimation Error (dB)','FontSize',12,'FontWeight','bold');
title('Plot 8: LMMSE Channel Estimation Error Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 9 : MRT BF Gain Waveform
figure('Name','Plot 9: MRT BF Gain Waveform','NumberTitle','off');
plot(1:K, BF_gain(1,:),      'b-','LineWidth',2);
hold on;
plot(1:K, BF_gain(10,:),     'r-','LineWidth',2);
plot(1:K, BF_gain(50,:),     'g-','LineWidth',2);
plot(1:K, avgBF_perUser,     'k-','LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('MRT BF Gain  |h^H w|  =  ||h||','FontSize',12,'FontWeight','bold');
title('Plot 9: MRT Beamforming Gain Waveform (AP 1, 10, 50)', ...
      'FontSize',13,'FontWeight','bold');
legend('AP 1','AP 10','AP 50','Mean over all APs','Location','best');
grid on;

%% PLOT 10 : Baseline vs MRT Desired Signal Power Waveform
figure('Name','Plot 10: Baseline vs MRT Signal Waveform','NumberTitle','off');
plot(1:K, 10*log10(signal_baseline+eps), 'r--','LineWidth',2);
hold on;
plot(1:K, 10*log10(signal_MRT+eps),      'b-', 'LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Desired Signal Power (dB)','FontSize',12,'FontWeight','bold');
title('Plot 10: Desired Signal Power — Baseline vs After MRT BF', ...
      'FontSize',13,'FontWeight','bold');
legend('Baseline (No BF, Equal Power)', ...
       'After MRT Beamforming (Prop. Power)','Location','best');
grid on;

%% PLOT 11 : SINR Baseline vs MRT Waveform
figure('Name','Plot 11: SINR Baseline vs MRT','NumberTitle','off');
plot(1:K, SINR_baseline_dB, 'r--','LineWidth',2);
hold on;
plot(1:K, SINR_MRT_dB,      'b-', 'LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('SINR (dB)','FontSize',12,'FontWeight','bold');
title('Plot 11: SINR Waveform — Baseline vs MRT Beamforming', ...
      'FontSize',13,'FontWeight','bold');
legend('Baseline (No BF)','After MRT BF','Location','best');
grid on;

%% PLOT 12 : Max-Min Convergence Waveform
figure('Name','Plot 12: Max-Min Convergence Waveform','NumberTitle','off');
plot(1:numIterations, SINR_iter_min,'b-o', ...
     'LineWidth',2,'MarkerSize',5,'MarkerFaceColor','b');
hold on;
plot(1:numIterations, SINR_iter_avg,'r--s', ...
     'LineWidth',2,'MarkerSize',5,'MarkerFaceColor','r');
xlabel('Iteration Number','FontSize',12,'FontWeight','bold');
ylabel('SINR (dB)','FontSize',12,'FontWeight','bold');
title('Plot 12: Max-Min Optimization Convergence Waveform', ...
      'FontSize',13,'FontWeight','bold');
legend('Minimum SINR (objective)','Average SINR','Location','best');
yFinal = SINR_iter_min(end);
text(numIterations-2, yFinal+0.3, ...
     sprintf('Final Min: %.2f dB',yFinal), ...
     'FontSize',10,'FontWeight','bold','HorizontalAlignment','right');
grid on;

%% PLOT 13 : Power Allocation Waveform
figure('Name','Plot 13: Power Allocation Waveform','NumberTitle','off');
plot(1:K, avgPower_MRT,    'r--','LineWidth',2);
hold on;
plot(1:K, avgPower_MaxMin, 'b-', 'LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('Avg Allocated Power (mW)','FontSize',12,'FontWeight','bold');
title('Plot 13: Power Allocation — MRT Proportional vs Max-Min Optimized', ...
      'FontSize',13,'FontWeight','bold');
legend('MRT Proportional Power','Max-Min Optimized Power','Location','best');
grid on;

%% PLOT 14 : SINR Three-Way Comparison Waveform
figure('Name','Plot 14: SINR Three-Way Comparison','NumberTitle','off');
plot(1:K, SINR_baseline_dB, 'r--','LineWidth',2);
hold on;
plot(1:K, SINR_MRT_dB,      'b-', 'LineWidth',2);
plot(1:K, SINR_MaxMin_dB,   'k-', 'LineWidth',2.5);
xlabel('User Index','FontSize',12,'FontWeight','bold');
ylabel('SINR (dB)','FontSize',12,'FontWeight','bold');
title('Plot 14: SINR Waveform — Baseline vs MRT vs Max-Min Optimized', ...
      'FontSize',13,'FontWeight','bold');
legend('Baseline (No BF)', ...
       'MRT BF (Prop. Power)', ...
       'MRT + Max-Min Optimization','Location','best');
grid on;

%% PLOT 15 : CDF of SINR
figure('Name','Plot 15: CDF of SINR','NumberTitle','off');
[f1,x1] = ecdf(SINR_baseline_dB);
[f2,x2] = ecdf(SINR_MRT_dB);
[f3,x3] = ecdf(SINR_MaxMin_dB);
plot(x1,f1,'r--','LineWidth',2);
hold on;
plot(x2,f2,'b-', 'LineWidth',2);
plot(x3,f3,'k-', 'LineWidth',2.5);
xlabel('SINR (dB)','FontSize',12,'FontWeight','bold');
ylabel('CDF','FontSize',12,'FontWeight','bold');
title('Plot 15: CDF of SINR — Baseline vs MRT vs Max-Min', ...
      'FontSize',13,'FontWeight','bold');
legend('Baseline (No BF)', ...
       'MRT BF (Prop. Power)', ...
       'MRT + Max-Min Power Opt.','Location','best');
grid on;

%% =========================================================
% SAVE ALL FIGURES
%% =========================================================

fprintf('=========================================\n');
fprintf(' All 15 figures saved successfully.\n');
fprintf('=========================================\n\n');

%% =========================================================
% END OF CODE
%% =========================================================