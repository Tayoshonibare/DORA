%Generate a waveform for Radio and test NV diamond


%Clean ups
try
    tlCamera.Disarm; tlCamera.Dispose; delete(serialNumbers);tlCameraSDK.Dispose;delete(tlCamera);
    release (tx);
    release (tx2);
catch
    pause(0.1);
end

clear all; close all;


fs = 2e6;

sw = dsp.SineWave;
sw.Amplitude = 1;
sw.Frequency = 0;
sw.ComplexOutput = true;
sw.SampleRate = fs;
sw.SamplesPerFrame = 10000;
txWaveform = sw();

tx = sdrtx('Pluto');
tx.RadioID = 'usb:0';
tx.BasebandSampleRate = fs;
tx.Gain = 0;

tx2 = sdrtx('Pluto');
tx2.RadioID = 'usb:1';
tx2.BasebandSampleRate = fs;
tx2.Gain = 0;


%Set Pluto max, min, start and step frequencies
CenterFrequency_MIN = 2.77e9;
CenterFrequency_MAX = 2.97e9;
CenterFrequency_STEP = 0.0001e9;
tx.CenterFrequency = CenterFrequency_MIN;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Camera loop
disp ("T: Loading camera DLLs");
NET.addAssembly([pwd, '\Thorlabs.TSI.TLCamera.dll']);

disp ("T: Spawning camera");
tlCameraSDK = Thorlabs.TSI.TLCamera.TLCameraSDK.OpenTLCameraSDK;

disp ("T: Discovering camera");
serialNumbers = tlCameraSDK.DiscoverAvailableCameras;
disp("T: " + num2str(serialNumbers.Count) +  " camera was discovered.");

disp ("T: Opening camera");
tlCamera = tlCameraSDK.OpenCamera(serialNumbers.Item(0), false);

disp ("T: Configuring camera");
tlCamera.ExposureTime_us = 8.5 * 1000; % Set exposure
tlCamera.Gain = 0;% Set gain
tlCamera.BlackLevel = 0; %Set black level
numberOfFramesToAcquire = 2;
tlCamera.MaximumNumberOfFramesToQueue = numberOfFramesToAcquire + 2;  % Set the FIFO buffer size
tlCamera.OperationMode = Thorlabs.TSI.TLCameraInterfaces.OperationMode.SoftwareTriggered;
tlCamera.FramesPerTrigger_zeroForUnlimited = 0;

tlCamera.ROIAndBin.ROIWidth_pixels = 4000; %Set ROIWidth_pixels
tlCamera.ROIAndBin.ROIHeight_pixels = 272; %Set ROIHeight_pixels
tlCamera.ROIAndBin.ROIOriginX_pixels = 0; %Set ROIOriginX_pixels
tlCamera.ROIAndBin.ROIOriginY_pixels = 0; %Set ROIOriginY_pixels
tlCamera.ROIAndBin.BinX = 4; %Set BinX
tlCamera.ROIAndBin.BinY = 4; %Set BinY

% Load color processing .NET assemblies
NET.addAssembly([pwd, '\Thorlabs.TSI.Demosaicker.dll']);
NET.addAssembly([pwd, '\Thorlabs.TSI.ColorProcessor.dll']);

% Initialize the demosaicker
demosaicker = Thorlabs.TSI.Demosaicker.Demosaicker;
% Create color processor SDK.
colorProcessorSDK = Thorlabs.TSI.ColorProcessor.ColorProcessorSDK;

% Query the default white balance matrix from camera. Alternatively
% can also use user defined white balance matrix.
defaultWhiteBalanceMatrix = tlCamera.GetDefaultWhiteBalanceMatrix;

% Query other relevant camera information
cameraColorCorrectionMatrix = tlCamera.GetCameraColorCorrectionMatrix;
bitDepth = int32(tlCamera.BitDepth);
colorFilterArrayPhase = tlCamera.ColorFilterArrayPhase;

% Create standard RGB color processing pipeline.
standardRGBColorProcessor = colorProcessorSDK.CreateStandardRGBColorProcessor(defaultWhiteBalanceMatrix,...
    cameraColorCorrectionMatrix, bitDepth);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

disp ("T: Arm & trigger camera");
tlCamera.Arm;
tlCamera.IssueSoftwareTrigger;

disp ("T: Warming camera up");
waittime = 10; timepassed = 0;
while timepassed < waittime
    pause(1);
    timepassed = timepassed + 1;
    disp(['Warm up: ' num2str(timepassed) ' of ' num2str(waittime) ' sec'])
end

while tx.CenterFrequency < CenterFrequency_MAX
    %Increase transmission frequency
    transmitRepeat(tx,txWaveform); transmitRepeat(tx2,txWaveform); 
    pause(0.1);
    disp ("T: TX RF at " + tx.CenterFrequency*1e-9 + "GHz");
    
    frameCount = 0;
    while frameCount < numberOfFramesToAcquire

        if (tlCamera.NumberOfQueuedFrames > 0)
            imageFrame = tlCamera.GetPendingFrameOrNull;

            if ~isempty(imageFrame)
                frameCount = frameCount + 1;

                % Get the image data as 1D uint16 array
                imageData = uint16(imageFrame.ImageData.ImageData_monoOrBGR);
                disp ("T: " + num2str(imageFrame.FrameNumber) + " Frame obtained");

                %Get image width and height
                imageHeight = imageFrame.ImageData.Height_pixels;
                imageWidth = imageFrame.ImageData.Width_pixels;


                %Image computation
                imageData_Avg_frame = round (mean(imageData,  "all"));

                %Plot image from camera
                imageData2D = reshape(uint16(imageData), [imageWidth, imageHeight]);
                figure (1), imagesc(imageData2D'), colormap(gray)
                pbaspect([imageWidth imageHeight 1]);
                set(gca,'XTick',[], 'YTick', []);

                %Add annontation to image
                annstr = ['Min: ', num2str(min(imageData)), ' || Max: ', num2str(max(imageData)), ' || AVG:', num2str(imageData_Avg_frame) ]; 
                delete(findall(gcf,'type','annotation'));
                ha = annotation('textbox',[0.1 0.1 0.1 0.1],'string',annstr);
                ha.BackgroundColor = [0.9 0.5 1];
                pbaspect([imageWidth imageHeight 1]);
                
                
                

            end

        else
            pause(1e-6)
        end

    end

    if exist('PL')
        PL = [PL imageData_Avg_frame]; 
        freq = [freq tx.CenterFrequency];
    else 
        PL = imageData_Avg_frame;
        freq = tx.CenterFrequency;
    end

    tx.CenterFrequency = tx.CenterFrequency + CenterFrequency_STEP;
    tx2.CenterFrequency = tx.CenterFrequency;
    % if tx.CenterFrequency == CenterFrequency_MAX
    %     tx.CenterFrequency = CenterFrequency_MIN;
    % end
    
    figure(2); clf; plot (freq *1e-9, PL, 'LineWidth', 2); hold on; grid;
    xlabel ('RF Frequency GHz'); ylabel('PL ADC'); title ('PL ADC vs RF frequency');
    legend ('PL ADC');

    % figure(3); clf; plot (PL, 'LineWidth', 2); hold on; grid;
    % xlabel ('Frame'); ylabel('PL ADC'); title ('PL ADC vs frame count');
    % legend ('PL')


end


disp ("T: Closing camera");
tlCamera.Disarm;
tlCamera.Dispose;
delete(serialNumbers);
tlCameraSDK.Dispose;
delete(tlCamera);




