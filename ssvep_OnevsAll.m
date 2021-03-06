function [ confMat, confMatK, accK ] = ssvep_OnevsAll( gdffile )

freqBands = [10, 15, 12];
[s, h] = sload(gdffile, 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-training-arjun-[2016.02.11-14.35.48].gdf', 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-training-shiva-[2016.01.31-20.34.25].gdf', 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-record-train-[2016.04.09-10.38.44].gdf', 0, 'OVERFLOWDETECTION:OFF'); % samit
%[s, h] = sload('ssvep-record-train-indra-3-[2016.03.31-23.42.46].gdf', 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-training-samit-[2016.02.09-15.55.56].gdf', 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-record-train-prithvi-1-[2016.04.01-13.16.54].gdf', 0, 'OVERFLOWDETECTION:OFF');
%[s, h] = sload('ssvep-record-gagan-[2016.04.01-23.12.08].gdf', 0, 'OVERFLOWDETECTION:OFF');
fs = h.SampleRate;
numChannels = h.NS;
%numChannels = 2;
s = s(:, 1:numChannels); % selection of channels
%s = s(:, [2, 3]);

stimCodes = [33024, 33025, 33026, 33027];
numClasses = size(stimCodes, 2) - 1;

% Samples considered for training. From 1.000 to 7.999 sec.
flickerStart = 1;   % default = 1
flickerEnd = 8;     % could also be called last offset
samplesTrain = (flickerEnd - flickerStart) * fs; % 1750 samples @ fs = 250 Hz
startOffset = flickerStart * fs;

% stimCoordinate is a matrix with each column representing coordinate in
% h.EVENT.TYP
% h.EVENT.POS points to the sample number in signal vector 's'

for i = 1:size(stimCodes, 2)
    stimCoordinate(:, i) = find(ismember(h.EVENT.TYP, stimCodes(i)));
end

stimCoordinate_flat = find(ismember(h.EVENT.TYP, stimCodes));

classSignal = [];
nonclassSignal = [];

epochTime = 0.5;            % in seconds
epochOverlap = 0.1;         % in seconds
overlap_factor = (epochTime - epochOverlap) / epochTime;
discardBuffer = (samplesTrain - (epochTime * fs)) / (epochOverlap * fs);

data = [];
label = [];

% Band-pass filtering is the first thing which happens and it is done over
% the complete signal and on all channels.
for i = 1:numClasses                 % 3 classes
    signal(:, :, i) = s;                        % array of matrices
    
    for j = 1:numChannels
        order = 4;
        % Band-pass filtering from -0.25 to +0.25 Hz
        lowFreq = (freqBands(i) - 0.25) * (2/fs);
        highFreq = (freqBands(i) + 0.25) * (2/fs);

        [B, A] = butter(order, [lowFreq, highFreq]);
        signal(:, j, i) = filter(B, A, signal(:, j, i));
    end
    
    tempData = [];
    for j = 1:size(stimCoordinate_flat, 1)
        feature = [];
        if ~ismember(stimCoordinate_flat(j), stimCoordinate(:, i+1))
            % trial sample chunk
            signalTrial = signal(h.EVENT.POS(stimCoordinate_flat(j)) + startOffset:h.EVENT.POS(stimCoordinate_flat(j)) + startOffset + samplesTrain - 1, :, i);
            tempInner = [];
            % epoching
            for k = 1:numChannels
                timeEpoch = buffer(signalTrial(:, k), epochTime * fs, ceil(overlap_factor * epochTime * fs));
                timeEpoch = timeEpoch(:, size(timeEpoch, 2) - discardBuffer:end);
                tempInner = [tempInner; log(1 + mean(timeEpoch .^ 2))];
            end
            feature = [feature; tempInner'];
            
            labelChunk = size(feature, 1);
            label((j - 1) * labelChunk + 1:j * labelChunk, i) = 4;
            % Using number 4 for non-class features.
        else
            % trial sample chunk
            signalTrial = signal(h.EVENT.POS(stimCoordinate_flat(j)) + startOffset:h.EVENT.POS(stimCoordinate_flat(j)) + startOffset + samplesTrain - 1, :, i);
            tempInner = [];
            % epoching
            for k = 1:numChannels
                timeEpoch = buffer(signalTrial(:, k), epochTime * fs, ceil(overlap_factor * epochTime * fs));
                timeEpoch = timeEpoch(:, size(timeEpoch, 2) - discardBuffer:end);
                tempInner = [tempInner; log(1 + mean(timeEpoch .^ 2))];
            end
            feature = [feature; tempInner'];
            
            labelChunk = size(feature, 1);
            label((j - 1) * labelChunk + 1: j * labelChunk, i) = stimCodes(i + 1) - stimCodes(1);
        end
        tempData = [tempData; feature];
    end
    data(:, :, i) = tempData;
end

% data is 2112 x 6 x 3 for 1 to 8 second duration.
% label is 2112 x 3

order = [];

%fprintf('\n--- Resubstitution ---\n');
for i = 1:numClasses
    order(i, :) = unique(label(:, i));
  
    %[w(:, :, i), b(:, :, i), predict(:, i)] = ldam2(data(:, :, i), label(:, i));
    [w(:, :, i), b(:, :, i), predict(:, i)] = ldam(data(:, :, i), data(:, :, i), label(:, i));
    %[predict(:, i), error(:, i)] = classify(data(:, :, i), data(:, :, i), label(:, i));
end

%finalDecision = sum(~ismember(predict, 4) .* predict, 2);
idealDecision = sum(~ismember(label, 4) .* label, 2);

for i = 1:length(idealDecision)
    if sum(predict(i, :) == 4) == 2
        for j = 1:size(predict, 2)
            if predict(i, j) ~= 4
                finalDecision(i) = predict(i, j);
            end
        end
    else
        finalDecision(i) = 0;
    end
end
finalDecision = finalDecision';

finalDecision(finalDecision == 0) = 4;
idealDecision(idealDecision == 0) = 4;

confMat = confusionmat(idealDecision, finalDecision);
%perc = bsxfun(@rdivide, confMat, sum(confMat,2)) * 100


confMatK = zeros(size(confMat));
%fprintf('\n--- KFold Crossvalidation ---\n');
indices = crossvalind('Kfold', label(:, 1), 10);    %10 fold
for j = 1:10
    test = (indices == j);
    train = ~test;
    kidealDecision = idealDecision(test);
    
    for i = 1:numClasses
        order(i, :) = unique(label(:, i));
       
        %[w(:, :, i), b(:, :, i), predict(:, i)] = ldam2(data(:, :, i), label(:, i));
        [kw(:, :, i), kb(:, :, i), kpredict(:, i)] = ldam(data(test, :, i), data(train, :, i), label(train, i));
        %[kpredict(:, i), kerror(:, i)] = classify(data(test, :, i), data(train, :, i), label(train, i));
    end
    
    for k = 1:length(kidealDecision)
        if sum(kpredict(k, :) == 4) == 2
            for l = 1:size(predict, 2)
                if kpredict(k, l) ~= 4
                    kfinalDecision(k) = kpredict(k, l);
                end
            end
        else
            kfinalDecision(k) = 0;
        end
    end
    
    kfinalDecision = kfinalDecision';
    kfinalDecision(kfinalDecision == 0) = 4;
    kidealDecision(kidealDecision == 0) = 4;
    
    confMatKj = confusionmat(kidealDecision, kfinalDecision);
    accK(j) = 100 * sum(diag(confMatKj)) / sum(sum(confMatKj));
    confMatK = confMatK + confMatKj;
    
    kb = []; kw = []; kpredict = []; kfinalDecision = []; % to avoid dimension mismatch in the non-equal partition
end
%confMatK
%percK = bsxfun(@rdivide, confMatK, sum(confMatK,2)) * 100
end