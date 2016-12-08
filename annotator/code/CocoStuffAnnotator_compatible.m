classdef CocoStuffAnnotator_compatible < handle & dynamicprops  %this is a handle and propertys can be added dynamicly
    % Image annotation class.
    %
    % Supports pixel and superpixel drawing.
    % All point coordinates are [y, x]
    % Input: 1-9 for labels, +- for scale, left/right click for add/remove
    %
    % Copyright by Holger Caesar, 2016
    
    properties
        % Main figure
        figMain
        containerButtons
        containerOptions
        containerStatus
        ax
        ui
        handleImage
        handleMap
        handleOverlay
        
        % Pick label specific
        figLabelHierarchy
        ysLabelHierarchyIn
        xsLabelHierarchyIn
        ysLabelHierarchyOut
        xsLabelHierarchyOut
        categoriesLabelHierarchyIn
        categoriesLabelHierarchyOut
        
        % Content fields
        labelIdx = 2;
        drawStatus = 0; % 0: nothing, 1: left mouse, 2: right mouse
        drawMode = 'superpixelDraw';
        drawOverwrite = false;
        drawSizes = [1, 2, 5, 10, 15, 20, 30, 50, 100]';
        drawSize = 1;
        drawColors % 1 is none
        drawColor
        drawTransparency = 0.6;
        overlayTransparency = 0.2;
        timerTotal
        timerImage
        timeImagePrevious
        
        enablePixelDrawing = false;
        enableMagicWand = false;
        enableGrabCut = false;
        
        % Administrative
        imageList
        labelNames
        datasetStuff
        dataFolder
        regionFolder
        maskFolder
        userName
        
        % Image-specific
        imageIdx
        imageSize
        image
        imageName
        regionMap
        regionBoundaries
        labelRegions
    end
    
    methods
        % Constructor
        function obj = CocoStuffAnnotator_compatible(varargin)
            
            % Initial settings
            p = inputParser;
            addParameter(p, 'datasetStuff', CocoStuffDatasetSimplified());
            addParameter(p, 'imageIdx', 1);
            parse(p, varargin{:});
            
            % Set as global options
            obj.datasetStuff = p.Results.datasetStuff;
            obj.imageIdx = p.Results.imageIdx;
            
            % Set timer
            obj.timerTotal = tic;
            
            % Setup folders
            codeFolder = fileparts(mfilename('fullpath'));
            obj.dataFolder = fullfile(fileparts(codeFolder), 'data');
            
            % Read user name
            userNamePath = fullfile(obj.dataFolder, 'input', 'user.txt');
            userName = readLinesToCell(userNamePath);
            assert(numel(userName) == 1 && ~isempty(userName));
            obj.userName = userName{1};
            
            % Setup user folders
            obj.regionFolder  = fullfile(obj.dataFolder, 'input',  'regions', 'slico-1000');
            obj.maskFolder = fullfile(obj.dataFolder, 'output', 'annotations', obj.userName);
            
            % Get image list
            imageListPath = fullfile(obj.dataFolder, 'input', 'imageLists', sprintf('%s.list', obj.userName));
            if ~exist(imageListPath, 'file')
                error('Error: Please check your username! Cannot find the imageList file at: %s\n', imageListPath);
            end
            obj.imageList = readLinesToCell(imageListPath);
            obj.imageList(cellfun(@isempty, obj.imageList)) = [];
            
            % Fix randomness
            rng(42);
            
            % Get dataset options
            stuffLabels = sort(obj.datasetStuff.getLabelNames());
            obj.labelNames = ['unlabeled'; 'none'; 'thingsImp'; 'things'; stuffLabels];
            labelCount = numel(obj.labelNames);
            unlabeledColor = [1, 1, 1];
            noneColor = [0, 0, 0];
            otherColors = jet(numel(stuffLabels)+1);
            thingColor = otherColors(1, :);
            stuffColors = otherColors(2:end, :);
            stuffColors = stuffColors(randperm(size(stuffColors, 1)), :);
            obj.drawColors = [unlabeledColor; noneColor; thingColor; thingColor; stuffColors];
            obj.drawColor = obj.drawColors(obj.labelIdx, :);
            assert(size(obj.drawColors, 1) == labelCount);
            
            % Create figure
            obj.figMain = figure(...
                'MenuBar', 'none',...
                'NumberTitle', 'off');
            obj.updateTitle();
            set(obj.figMain, 'CloseRequestFcn', @(src,event) onclose(obj,src,event))
            
            % Set figure size
            figSize = [800, 800];
            figPos = get(obj.figMain, 'Position');
            figPos(3) = figSize(2);
            figPos(4) = figSize(1);
            set(obj.figMain, 'Position', figPos);
            
            % Create form containers
            menuLeft = 0.0;
            menuRight = 1.0;
            obj.containerButtons = uiflowcontainer('v0', obj.figMain, 'Units', 'Norm', 'Position', [menuLeft, .95, menuRight, .05]);
            obj.containerOptions = uiflowcontainer('v0', obj.figMain, 'Units', 'Norm', 'Position', [menuLeft, .90, menuRight, .05]);
            
            % Create buttons
            obj.ui.buttonLabelHierarchy = uicontrol(obj.containerButtons, ...
                'String', 'Label hierarchy', ...
                'Callback', @(handle, event) buttonLabelHierarchyClick(obj, handle, event), ...
                'Tag', 'buttonLabelHierarchy');
            
            obj.ui.buttonPickLabel = uicontrol(obj.containerButtons, ...
                'String', 'Pick label', ...
                'Callback', @(handle, event) buttonPickLabelClick(obj, handle, event), ...
                'Tag', 'buttonPickLabel');
            
            if obj.enablePixelDrawing
                obj.ui.buttonPixelDraw = uicontrol(obj.containerButtons, ...
                    'Style', 'togglebutton', ...
                    'String', 'Pixel drawing', ...
                    'Callback', @(handle, event) buttonPixelDrawClick(obj, handle, event), ...
                    'Tag', 'buttonPixelDraw');
                set(obj.ui.buttonPixelDraw, 'Value', 0);
                
                obj.ui.buttonDrawSuperpixelDraw = uicontrol(obj.containerButtons, ...
                    'Style', 'togglebutton', ...
                    'String', 'Superpixel drawing', ...
                    'Callback', @(handle, event) buttonSuperpixelDrawClick(obj, handle, event), ...
                    'Tag', 'buttonSuperpixelDraw');
                set(obj.ui.buttonSuperpixelDraw, 'Value', 1);
            end
            
            if obj.enableGrabCut
                obj.ui.buttonLearnLabel = uicontrol(obj.containerButtons, ...
                    'String', 'Learn label', ...
                    'Callback', @(handle, event) buttonLearnLabelClick(obj, handle, event), ...
                    'Tag', 'buttonLearnLabel');
            end
            
            if obj.enableMagicWand
                obj.ui.buttonMagicWand = uicontrol(obj.containerButtons, ...
                    'String', 'Magic wand', ...
                    'Callback', @(handle, event) buttonMagicWandClick(obj, handle, event), ...
                    'Tag', 'buttonMagicWand');
            end
            
            obj.ui.buttonClearLabel = uicontrol(obj.containerButtons, ...
                'String', 'Clear label', ...
                'Callback', @(handle, event) buttonClearLabelClick(obj, handle, event), ...
                'Tag', 'buttonClearLabel');
            
            obj.ui.buttonPrevImage = uicontrol(obj.containerButtons, ...
                'String', 'Prev image', ...
                'Callback', @(handle, event) buttonPrevImageClick(obj, handle, event), ...
                'Tag', 'buttonPrevImage');
            
            obj.ui.buttonJumpImage = uicontrol(obj.containerButtons, ...
                'String', 'Jump to image', ...
                'Callback', @(handle, event) buttonJumpImageClick(obj, handle, event), ...
                'Tag', 'buttonJumpImage');
            
            obj.ui.buttonNextImage = uicontrol(obj.containerButtons, ...
                'String', 'Next image', ...
                'Callback', @(handle, event) buttonNextImageClick(obj, handle, event), ...
                'Tag', 'buttonNextImage');
            
            % Create options
            labelNamesPopup = obj.labelNames;
            labelNamesPopup(strcmp(labelNamesPopup, 'unlabeled')) = [];
            labelNamesPopup(strcmp(labelNamesPopup, 'thingsImp')) = [];
            obj.ui.popupLabel = uicontrol(obj.containerOptions, ...
                'Style', 'popupmenu', ...
                'String', labelNamesPopup, ...
                'Callback', @(handle, event) popupLabelSelect(obj, handle, event));
            
            obj.ui.popupPointSize = uicontrol(obj.containerOptions, ...
                'Style', 'popupmenu', ...
                'String', cellfun(@num2str, mat2cell(obj.drawSizes, ones(size(obj.drawSizes))), 'UniformOutput', false), ...
                'Value', find(obj.drawSizes == obj.drawSize), ...
                'Callback', @(handle, event) popupPointSizeSelect(obj, handle, event));
            
            obj.ui.checkOverwrite = uicontrol(obj.containerOptions, ...
                'Style', 'checkbox',...
                'String', 'Overwrite',...
                'Value', obj.drawOverwrite, ...
                'Callback', @(handle, event) checkOverwriteChange(obj, handle, event));
            
            obj.ui.sliderMapTransparency = uicontrol(obj.containerOptions, ...
                'Style', 'slider', ...
                'Min', 0, 'Max', 100, 'Value', 100 * obj.drawTransparency, ...
                'Callback', @(handle, event) sliderMapTransparencyChange(obj, handle, event));
            
            obj.ui.sliderOverlayTransparency = uicontrol(obj.containerOptions, ...
                'Style', 'slider', ...
                'Min', 0, 'Max', 100, 'Value', 100 * obj.overlayTransparency, ...
                'Callback', @(handle, event) sliderOverlayTransparencyChange(obj, handle, event));

            % Make sure labelIdx is the same everywhere
            obj.setLabelIdx(obj.labelIdx);
            
            % Specify axes
            obj.ax = axes('Parent', obj.figMain);
            obj.figResize();
            axis(obj.ax, 'off');
            
            % Show empty image
            axes(obj.ax);
            hold on;
            colormap(obj.ax, obj.drawColors);
            
            obj.handleImage = imshow([]);
            obj.handleMap = image([]); %#ok<CPROP>
            obj.handleOverlay = image([]); %#ok<CPROP>
            hold off;
            
            % Set axis units
            obj.ax.Units = 'pixels';
            
            % Image event callbacks
            set(obj.handleMap, 'ButtonDownFcn', @(handle, event) handleClickDown(obj, handle, event));
            set(obj.handleOverlay, 'ButtonDownFcn', @(handle, event) handleClickDown(obj, handle, event));
            
            % Figure event callbacks
            set(obj.figMain, 'WindowButtonMotionFcn', @(handle, event) figMouseMove(obj, handle, event));
            set(obj.figMain, 'WindowButtonUpFcn', @(handle, event) figClickUp(obj, handle, event));
            set(obj.figMain, 'ResizeFcn', @(handle, event) figResize(obj, handle, event));
            set(obj.figMain, 'KeyPressFcn', @(handle, event) figKeyPress(obj, handle, event));
            set(obj.figMain, 'WindowScrollWheelFcn', @(handle, event) figScrollWheel(obj, handle, event));
            
            % Set fancy mouse pointer
            setCirclePointer(obj.figMain);
            
            % Load image
            obj.loadImage();
        end
        
        function loadImage(obj)
            % Reads the current imageIdx
            % Resets all image-specific settings and loads a new image
            
            % Set timer
            obj.timerImage = tic;
            
            % Load image
            obj.imageName = obj.imageList{obj.imageIdx};
            obj.image     = obj.datasetStuff.getImage(obj.imageName);
            obj.imageSize = size(obj.image);
            
            % Load regions from file
            regionPath = fullfile(obj.regionFolder, sprintf('%s.mat', obj.imageName));
            if exist(regionPath, 'file')
                regionStruct = load(regionPath, 'regionMap', 'regionBoundaries', 'labelMapThings');
                obj.regionMap = regionStruct.regionMap;
                obj.regionBoundaries = regionStruct.regionBoundaries;
                labelMapThings = regionStruct.labelMapThings;
            else
                error('Error: Cannot find region file: %s\n', regionPath);
            end
            
            % Load annotation if it already exists
            maskPath = fullfile(obj.maskFolder, sprintf('mask-%s.mat', obj.imageName));
            if exist(maskPath, 'file')
                fprintf('Loading existing annotation mask %s...\n', maskPath);
                maskStruct = load(maskPath, 'labelMap', 'timeImage', 'labelNames');
                labelMap = maskStruct.labelMap;
                obj.timeImagePrevious = maskStruct.timeImage;
                
                % Make sure labels haven't changed since last time
                savedLabelNames = maskStruct.labelNames;
                assert(isequal(savedLabelNames, obj.labelNames));
                
                assert(obj.imageSize(1) == size(labelMap, 1) && obj.imageSize(2) == size(labelMap, 2) && size(labelMap, 3) == 1);
            else
                fprintf('Creating new annotation mask %s...\n', maskPath);
                labelMap = ones(obj.imageSize(1), obj.imageSize(2));
                labelMap(labelMapThings == 3) = 3;
                obj.timeImagePrevious = 0;
            end
            assert(min(labelMap(:)) >= 1);
            
            % Show images
            obj.handleImage.CData = obj.image;
            obj.handleMap.CData = labelMap;
            
            % Create labelRegions
            obj.transferPixelToSuperpixelLabels();
            
            % Update alpha data
            obj.updateAlphaData();
            
            % Show boundaries
            overlayIm = zeros(obj.imageSize);
            overlayIm(:, :, 1) = 1;
            obj.handleOverlay.CData = overlayIm;
            
            % Update figure title
            obj.updateTitle();
        end
        
        % Button callbacks
        function buttonLabelHierarchyClick(obj, handle, event) %#ok<INUSD>
            if isempty(obj.figLabelHierarchy) || ~isvalid(obj.figLabelHierarchy)
                % Open new figure
                obj.figLabelHierarchy = figure('Name', 'Label hierarchy', ...
                    'MenuBar', 'none',...
                    'NumberTitle', 'off');
            else
                % Make figure active again
                figure(obj.figLabelHierarchy);
            end
                        
            % Get label hierarchy
            [nodes, cats, heights] = obj.datasetStuff.getClassHierarchy();
            
            % Plot label hierarchy
            obj.plotTree(nodes, cats, heights, 1);
            obj.plotTree(nodes, cats, heights, 2);
            
            % Set figure size
            pos = get(obj.figLabelHierarchy, 'Position');
            newPos = pos;
            newPos(3) = 1000;
            newPos(4) = 800;
            set(obj.figLabelHierarchy, 'Position', newPos);
        end
        
        function buttonPickLabelClick(obj, handle, event) %#ok<INUSD>
            obj.drawMode = 'pickLabel';
        end
        
        function plotTree(obj, nodes, cats, heights, isIndoors) % isIndoors: indoors = 1, outdoors = 2
            % Get only relevant nodes and cats
            sel = false(size(nodes));
            if isIndoors == 1
                sel(2) = true;
            else
                sel(3) = true;
            end
            while true
                oldSel = sel;
                sel = sel | ismember(nodes, find(sel));
                if isequal(sel, oldSel)
                    break;
                end
            end
            nodes = nodes(sel);
            cats = cats(sel);
            heights = heights(sel);
            
            % Remap nodes in 0:x range
            map = false(max(nodes), 1);
            map(unique(nodes)) = true;
            map = cumsum(map)-1;
            nodes = map(nodes);
            
            % Plot them
            ax = axes('Parent', obj.figLabelHierarchy, 'Units', 'Norm');
            axis(ax, 'off');
            treeplot(nodes');
            if isIndoors == 1
                set(ax, 'Position', [0, 0, 0.5, 1]);
            else
                set(ax, 'Position', [0.5, 0, 0.5, 1]);
            end
            [xs, ys] = treelayout(nodes);
            
            % Set appearance settings and show labels
            isLeaf = ys == min(ys);
            textInner = text(xs(~isLeaf) + 0.01, ys(~isLeaf) - 0.025, cats(~isLeaf), 'VerticalAlignment', 'Bottom', 'HorizontalAlignment', 'right');
            textLeaf  = text(xs( isLeaf) - 0.01, ys( isLeaf) - 0.02,  cats( isLeaf), 'VerticalAlignment', 'Bottom', 'HorizontalAlignment', 'left');
            set(ax, 'XTick', [], 'YTick', [], 'Units', 'Normalized');
            ax.XLabel.String = '';
            
            % Rotate view
            camroll(90);
            
            % Store only selectable/leaf nodes
            selectable = heights == 3;
            cats = cats(selectable);
            ys = ys(selectable);
            xs = xs(selectable);
            
            if isIndoors == 1
                % Save to object
                obj.categoriesLabelHierarchyIn = cats;
                obj.ysLabelHierarchyIn = ys;
                obj.xsLabelHierarchyIn = xs;
                
                % Register callbacks
                set(ax, 'ButtonDownFcn', @(handle, event) pickLabelInClick(obj, handle, event));
                set(textInner, 'ButtonDownFcn', @(handle, event) pickLabelInClick(obj, handle, event));
                set(textLeaf, 'ButtonDownFcn', @(handle, event) pickLabelInClick(obj, handle, event));
            else
                % Save to object
                obj.categoriesLabelHierarchyOut = cats;
                obj.ysLabelHierarchyOut = ys;
                obj.xsLabelHierarchyOut = xs;
                
                % Register callbacks
                set(ax, 'ButtonDownFcn', @(handle, event) pickLabelOutClick(obj, handle, event));
                set(textInner, 'ButtonDownFcn', @(handle, event) pickLabelOutClick(obj, handle, event));
                set(textLeaf, 'ButtonDownFcn', @(handle, event) pickLabelOutClick(obj, handle, event));
            end            
        end
        
        function pickLabelInClick(obj, ~, event)
            % Find closest label indoors
            pos = [event.IntersectionPoint(2), event.IntersectionPoint(1)];
            
            dists = sqrt((obj.ysLabelHierarchyIn - pos(1)) .^ 2 + (obj.xsLabelHierarchyIn - pos(2)) .^ 2);
            [~, minDistInd] = min(dists);
            
            labelName = obj.categoriesLabelHierarchyIn(minDistInd);
            labelIdx = find(strcmp(obj.labelNames, labelName));
            
            % Set globally
            obj.setLabelIdx(labelIdx); %#ok<FNDSB>
        end
        
        function pickLabelOutClick(obj, ~, event)
            % Find closest label indoors
            pos = [event.IntersectionPoint(2), event.IntersectionPoint(1)];
            
            dists = sqrt((obj.ysLabelHierarchyOut - pos(1)) .^ 2 + (obj.xsLabelHierarchyOut - pos(2)) .^ 2);
            [~, minDistInd] = min(dists);
            
            labelName = obj.categoriesLabelHierarchyOut(minDistInd);
            labelIdx = find(strcmp(obj.labelNames, labelName));
            
            % Set globally
            obj.setLabelIdx(labelIdx); %#ok<FNDSB>
        end
        
        function buttonPixelDrawClick(obj, handle, event) %#ok<INUSD>
            obj.drawMode = 'pixelDraw';
            
            set(obj.ui.buttonPixelDraw, 'Value', 1);
            set(obj.ui.buttonSuperpixelDraw, 'Value', 0);
        end
        
        function buttonSuperpixelDrawClick(obj, handle, event) %#ok<INUSD>
            obj.drawMode = 'superpixelDraw';
            
            set(obj.ui.buttonPixelDraw, 'Value', 0);
            set(obj.ui.buttonSuperpixelDraw, 'Value', 1);
        end
        
        function buttonLearnLabelClick(obj, handle, event) %#ok<INUSD>
            methodTimer = tic;
            
            % Check if there are sp annotations for current label
            initSpMask = obj.labelRegions == obj.labelIdx;
            if obj.labelIdx == 1
                msgbox('Cannot learn "unlabeled" label!', 'Error', 'error', 'replace');
                return;
            end
            if ~any(initSpMask)
                msgbox('Need to annotate superpixels with current label before learning!', 'Error', 'error', 'replace');
                return;
            end
            
            % Options
            maxIterations = 500;
            
            % Run grabcut
            splabels = uint16(obj.regionMap);
            image = im2uint8(obj.image);
            
            if false
                % Settings
                constrainToInit = false; %#ok<UNRCH>
                
                % Hard mask
                seg = segment_superpixels_from_hardmask(spstats, initSpMask, constrainToInit, maxIterations);
            else
                % Settings
                neutralVal = 0.5;
                threshold = 0.5;
                posVal = 1.0;
                negVal = 0.0;
                
                % Soft mask
                labelMap = obj.handleMap.CData;
                mask = ones(size(labelMap)) * neutralVal;
                mask(labelMap == obj.labelIdx) = posVal;
                mask(labelMap ~= obj.labelIdx & labelMap ~= 1) = negVal;
                
                maskstat = sp_maskstat(mask, splabels);
                spstats = sp_stats_for_grabcut(image, splabels);
                seg = segment_superpixels_with_softmask(spstats, maskstat, threshold, maxIterations);
            end
            
            % Update superpixels
            spInds = find(seg & obj.labelRegions == 1); % Only label prev. unlabeled pixels
            spIndsIsOverwrite = (obj.drawOverwrite | obj.labelRegions(spInds) == 1) & obj.labelRegions(spInds) ~= 3;
            obj.labelRegions(spInds(spIndsIsOverwrite)) = obj.labelIdx;
            
            % Update shown pixels
            mask = ismember(obj.regionMap, spInds);
            [selY, selX] = find(mask);
            inds = sub2ind(obj.imageSize(1:2), selY, selX);
            indsIsOverwrite = (obj.drawOverwrite | obj.handleMap.CData(inds) == 1) & obj.handleMap.CData(inds) ~= 3;
            obj.handleMap.CData(inds(indsIsOverwrite)) = obj.labelIdx;
            obj.updateAlphaData();
            
            % Print time
            methodTime = toc(methodTimer);
            fprintf('Learned annotation took %.1fs.\n', methodTime);
        end
        
        function buttonMagicWandClick(obj, handle, event) %#ok<INUSD>
            obj.drawMode = 'magicWand';
        end
        
        function buttonClearLabelClick(obj, handle, event) %#ok<INUSD>
            
            % Set all labels to 1 (unlabeled)
            obj.handleMap.CData(obj.handleMap.CData(:) == obj.labelIdx) = 1;
            obj.labelRegions(obj.labelRegions(:) == obj.labelIdx) = 1;
            
            obj.updateAlphaData();
        end
        
        function saveMask(obj)
            % Check if anything was annotated
            labelMap = obj.handleMap.CData;
            maskPath = fullfile(obj.maskFolder, sprintf('mask-%s.mat', obj.imageName));
            if all(labelMap(:) == 1)
                fprintf('Not saving annotation for unedited image %s...\n', maskPath);
                return;
            end
            
            % Create folder
            if ~exist(obj.maskFolder, 'dir')
                mkdir(obj.maskFolder)
            end
            
            % Save mask
            fprintf('Saving annotation mask to %s...\n', maskPath);
            saveStruct.imageIdx = obj.imageIdx;
            saveStruct.imageSize = obj.imageSize;
            saveStruct.imageName = obj.imageName;
            saveStruct.labelMap = labelMap;
            saveStruct.labelNames = obj.labelNames;
            saveStruct.timeTotal = toc(obj.timerTotal);
            saveStruct.timeImage = obj.timeImagePrevious + toc(obj.timerImage);
            saveStruct.userName = obj.userName;
            save(maskPath, '-struct', 'saveStruct', '-v7.3');
        end
        
        function transferPixelToSuperpixelLabels(obj)
            % Make sure that the labelRegions field contains all superpixels that are covered by just one class.
            
            % Reset obj.labelRegions
            regionCount = max(obj.regionMap(:));
            obj.labelRegions = ones(regionCount, 1);
            
            labelMap = obj.handleMap.CData;
            relPixMap = labelMap ~= 1;
            relSPs = unique(obj.regionMap(relPixMap));
            for relSpIdx = 1 : numel(relSPs)
                relSp = relSPs(relSpIdx);
                sel = obj.regionMap == relSp;
                selLabels = unique(labelMap(sel));
                selLabels(selLabels == 1) = [];
                if numel(selLabels) == 1
                    obj.labelRegions(relSp) = selLabels;
                end
            end
        end
        
        function buttonPrevImageClick(obj, handle, event) %#ok<INUSD>
            % Check if image is complete
            if obj.checkUnlabeled()
                choice = questdlg('There are unlabeled pixels. Would you like to continue?', 'Continue?');
                switch choice
                    case 'Yes'
                        % do nothing
                    otherwise
                        return;
                end
            end
            
            % Save current mask
            obj.saveMask();
            
            % Set new imageIdx
            obj.imageIdx = obj.imageIdx - 1;
            if obj.imageIdx < 1
                obj.imageIdx = numel(obj.imageList);
            end
            
            % Load new image
            obj.loadImage();
        end
        
        function buttonJumpImageClick(obj, handle, event) %#ok<INUSD>
            % Check if image is complete
            if obj.checkUnlabeled()
                choice = questdlg('There are unlabeled pixels. Would you like to continue?', 'Continue?');
                switch choice
                    case 'Yes'
                        % do nothing
                    otherwise
                        return;
                end
            end
            
            % Ask for imageIdx
            message = sprintf('You are currently at image %d of %d. Please insert the number of the image you want to annotate (1 <= x <= %d):', obj.imageIdx, numel(obj.imageList), numel(obj.imageList));
            response = inputdlg(message);
            try
                response = str2double(response);
                if isempty(response)
                    % If the user cancelled the dialog, exit
                    return;
                end
                if isnan(response)
                    error('Error: Invalid number!');
                end
                if response < 1 || (numel(obj.imageList) < response)
                    error('Error: Number not in valid range: 1 <= x <= %d', numel(obj.imageList));
                end
                if mod(response, 1) ~= 0
                    error('Error: Only integers allowed!');
                end
            catch e
                msgbox(e.message, 'Error', 'error');
                return;
            end
            
            % Save current mask
            obj.saveMask();
            
            % Set new imageIdx
            obj.imageIdx = response;
            
            % Load new image
            obj.loadImage();
        end
        
        function buttonNextImageClick(obj, handle, event) %#ok<INUSD>
            % Check if image is complete
            if obj.checkUnlabeled()
                choice = questdlg('There are unlabeled pixels. Would you like to continue?', 'Continue?');
                switch choice
                    case 'Yes'
                        % do nothing
                    otherwise
                        return;
                end
            end
            
            % Save current mask
            obj.saveMask();
            
            % Set new imageIdx
            obj.imageIdx = obj.imageIdx + 1;
            if obj.imageIdx > numel(obj.imageList)
                obj.imageIdx = 1;
            end
            
            % Load new image
            obj.loadImage();
        end
        
        function[res] = checkUnlabeled(obj)            
            res = any(obj.handleMap.CData(:) == 1);
        end
        
        function popupLabelSelect(obj, handle, event) %#ok<INUSD>
            % Set label
            labels = get(handle, 'string');
            selection = get(handle, 'value');
            label = labels{selection};
            labelIdx = find(strcmp(obj.labelNames, label));
            obj.setLabelIdx(labelIdx); %#ok<FNDSB>
        end
        
        function setLabelIdx(obj, labelIdx)
            % Set new value
            obj.labelIdx = labelIdx;
            if isempty(obj.labelIdx)
                error('Internal error: Unknown label picked!');
            end
            
            % Set popup value
            val2 = get(obj.ui.popupLabel, 'String');
            set(obj.ui.popupLabel, 'Value', find(strcmp(val2, obj.labelNames{obj.labelIdx})));
            
            % Update color
            obj.drawColor = obj.drawColors(obj.labelIdx, :);
        end
        
        function popupPointSizeSelect(obj, handle, event) %#ok<INUSD>
            values = get(handle, 'string');
            selection = get(handle, 'value');
            obj.drawSize = str2double(values{selection});
        end
        
        function checkOverwriteChange(obj, handle, ~)
            obj.drawOverwrite = handle.Value;
        end
        
        function sliderMapTransparencyChange(obj, ~, event)
            obj.drawTransparency = event.Source.Value / 100;
            obj.updateAlphaData();
        end
        
        function sliderOverlayTransparencyChange(obj, ~, event)
            obj.overlayTransparency = event.Source.Value / 100;
            obj.updateAlphaData();
        end
        
        function handleClickDown(obj, handle, event) %#ok<INUSL>
            pos = round([event.IntersectionPoint(2), event.IntersectionPoint(1)]);
            if event.Button == 1
                obj.drawStatus = 1;
            elseif event.Button == 3
                obj.drawStatus = 2;
            end
            obj.drawPos(pos);
        end
        
        function figClickUp(obj, ~, ~)
            obj.drawStatus = 0;
        end
        
        function drawPos(obj, pos)
            if obj.drawStatus ~= 0
                if strcmp(obj.drawMode, 'pickLabel')
                    labelIdx = obj.handleMap.CData(pos(1), pos(2));
                    
                    if labelIdx ~= 1
                        % Correct from read-only things to addable things
                        if labelIdx == 3
                            labelIdx = 4;
                        end
                        
                        % Update labelIdx globally
                        obj.setLabelIdx(labelIdx);
                    end
                        
                    % Set to drawing mode
                    obj.drawMode = 'superpixelDraw';
                elseif strcmp(obj.drawMode, 'magicWand')
                    % Compute region adjacency matrix
                    
                    %TODO
                else
                    if obj.drawStatus == 1
                        labelIdx = obj.labelIdx;
                    elseif obj.drawStatus == 2
                        labelIdx = 1;
                    end
                
                    % Draw current circle on pixels or superpixels
                    if false
                        % Square
                        selY = max(1, pos(1)-obj.drawSize) : min(pos(1)+obj.drawSize, obj.imageSize(1)); %#ok<UNRCH>
                        selX = max(1, pos(2)-obj.drawSize) : min(pos(2)+obj.drawSize, obj.imageSize(2));
                        [selX, selY] = meshgrid(selX, selY);
                    else
                        % Circle
                        xs = pos(2)-obj.drawSize : pos(2)+obj.drawSize;
                        ys = pos(1)-obj.drawSize : pos(1)+obj.drawSize;
                        [XS, YS] = meshgrid(xs, ys);
                        dists = sqrt((XS - pos(2)) .^ 2 + (YS - pos(1)) .^ 2);
                        valid = dists <= obj.drawSize - 0.1 & XS >= 1 & XS <= obj.imageSize(2) & YS >= 1 & YS <= obj.imageSize(1);
                        selX = XS(valid);
                        selY = YS(valid);
                    end
                    
                    if strcmp(obj.drawMode, 'pixelDraw')
                        inds = sub2ind(obj.imageSize(1:2), selY, selX);
                        indsIsOverwrite = (labelIdx == 1 | obj.drawOverwrite | obj.handleMap.CData(inds) == 1) & obj.handleMap.CData(inds) ~= 3;
                        obj.handleMap.CData(inds(indsIsOverwrite)) = labelIdx;
                    elseif strcmp(obj.drawMode, 'superpixelDraw')
                        % Find selected superpixel and create its mask
                        regionMapInds = sub2ind(size(obj.regionMap), selY, selX);
                        spInds = unique(obj.regionMap(regionMapInds));
                        mask = ismember(obj.regionMap, spInds);
                        [selY, selX] = find(mask);
                        inds = sub2ind(obj.imageSize(1:2), selY, selX);
                        indsIsOverwrite = (labelIdx == 1 | obj.drawOverwrite | obj.handleMap.CData(inds) == 1) & obj.handleMap.CData(inds) ~= 3;
                        obj.handleMap.CData(inds(indsIsOverwrite)) = labelIdx;
                        
                        % Set superpixel labels
                        spIndsIsOverwrite = (labelIdx == 1 | obj.drawOverwrite | obj.labelRegions(spInds) == 1) & obj.labelRegions(spInds) ~= 3;
                        obj.labelRegions(spInds(spIndsIsOverwrite)) = labelIdx;
                    end
                    
                    % Update alpha data
                    obj.updateAlphaData();
                end
            end
        end
        
        function updateAlphaData(obj)
            set(obj.handleMap, 'AlphaData', obj.drawTransparency * double(obj.handleMap.CData ~= 1));
            set(obj.handleOverlay, 'AlphaData', obj.overlayTransparency * obj.regionBoundaries);
        end
        
        function figMouseMove(obj, ~, ~)
            % Update timer in figure title
            obj.updateTitle();
            
            imPoint = round(get(obj.ax, 'CurrentPoint'));
            imPoint = [imPoint(1, 2), imPoint(1, 1)];
            
            if 1 <= imPoint(1) && imPoint(1) <= obj.imageSize(1) && ...
                    1 <= imPoint(2) && imPoint(2) <= obj.imageSize(2)
                obj.drawPos(imPoint);
            end
        end
        
        function updateTitle(obj)
            
            timeImage = obj.timeImagePrevious;
            if ~isempty(obj.timerImage)
                timeImage = timeImage + toc(obj.timerImage);
            end
            set(obj.figMain, 'Name', sprintf('CocoStuffAnnotator v0.5 - %s - %s (%d / %d) - %.1fs', obj.userName, obj.imageName, obj.imageIdx, numel(obj.imageList), timeImage));
        end
        
        function figResize(obj, ~, ~)
            yEnd   = 0.9;
            yStart = 0.0;
            ySize = yEnd - yStart;
            
            set(obj.ax, 'Units', 'Norm', 'Position', [0.0, yStart, 1, ySize]);
        end
        
        function figKeyPress(obj, ~, event)
            if strcmp(event.EventName, 'KeyPress')
                if isempty(event.Character)
                    % Do nothing
                elseif strcmp(event.Character, '+')
                    val1 = get(obj.ui.popupPointSize, 'Value');
                    val2 = get(obj.ui.popupPointSize, 'String');
                    set(obj.ui.popupPointSize, 'Value', min(val1 + 1, numel(val2)));
                    obj.drawSize = str2double(val2{val1});
                elseif strcmp(event.Character, '-')
                    val1 = get(obj.ui.popupPointSize, 'Value');
                    val2 = get(obj.ui.popupPointSize, 'String');
                    set(obj.ui.popupPointSize, 'Value', max(val1 - 1, 1));
                    obj.drawSize = str2double(val2{val1});
                end
            end
        end
        
        function figScrollWheel(obj, ~, event)
            val = get(obj.ui.popupPointSize, 'Value') + event.VerticalScrollCount;
            val = min(val, numel(get(obj.ui.popupPointSize, 'String')));
            val = max(val, 1);
            set(obj.ui.popupPointSize, 'Value', val);
            val1 = get(obj.ui.popupPointSize, 'Value');
            val2 = get(obj.ui.popupPointSize, 'String');
            obj.drawSize = str2double(val2{val1});
        end
        
        %This Callback is called when the object is deleted
        function delete(obj)
            if ishandle(obj.figMain)
                close(obj.figMain)
            end
        end
        
        %If someone closes the figure than everything will be deleted !
        function onclose(obj, src, event) %#ok<INUSD>
            
            % Close other windows
            if ishandle(obj.figLabelHierarchy)
                close(obj.figLabelHierarchy);
            end
            
            delete(src)
            delete(obj)
        end
    end
end