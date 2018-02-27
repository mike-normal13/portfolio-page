/** represents _nBanks X _nPads */
private var _soundCollection: [[PadModel?]?]! = [];

/** every pad will have its own mixer,
            i.e. each of the player nodes associtaed with a pad will connect to a mixer node,
            thereby making it easier to adjust settings such as volume for all player nodes at once.
            each pad mixer node will be attached to the mixer node assigned to each bank */
private var _padMixerArray: [[AVAudioMixerNode?]] = [];

private var _fadeOutTimerInterval = 0.001;

private var _fadeCountArray: [[Int]] = [];
private var _fadeScalarArray: [[Double]] = [];

/** used to apply instant fade out when a pad is released by the user */
    private var _releaseTimerArray: [[Timer?]] = [];

/** stop playing the pad corresponding to the bank and pad number */
    func stop(bank: Int, pad: Int, preview: Bool)
    {
        _releaseTimerArray[bank][pad] = Timer()
        
        // without this, the mixer node's volume will stay at zero once the fade completes.
        var preFadeVolume: Float = 0.0;
        
        // _soundCollection is a 2d array of my PadModel class
        preFadeVolume = (_soundCollection[bank]![pad]?.volume)!
        
                
        if((_releaseTimerArray[bank][pad] == nil))
        {
            _releaseTimerArray[bank][pad] = Timer.scheduledTimer(timeInterval: _fadeOutTimerInterval, target: self, selector: #selector(self.fadeout(timer:)), userInfo: (bank, pad, preFadeVolume, preview), repeats: true);
        }
        
        // Don't for get to invalidate your timers    
        if(_soundCollection[bank]![pad] != nil)
        {
            _volumeDataTimerArray[bank][pad]?.invalidate();
            _volumeDataTimerArray[bank][pad] = nil;            
        }
    }

    /** apply a real time fade out if the pad is stopped before its set endpoint
            this method is used by a timer.*/
    @objc func fadeout(timer: Timer)
    {
         // (bankNumber, padNumber, preFadeVolume, preview)
        let userInfo = timer.userInfo as! (Int, Int, Float, Bool);
        
        // linear fade
        _fadeScalarArray[userInfo.0][userInfo.1] -= _fadeDecrement; // 1/32
    
        _padMixerArray[userInfo.0][userInfo.1]?.volume = Float(_fadeScalarArray[userInfo.0][userInfo.1]) * userInfo.2;
        
        if(_fadeCountArray[userInfo.0][userInfo.1] == _fadeSpan)
        {
            if(_soundCollection[userInfo.0]![userInfo.1]?.isPlaying)!
            {
                // stop PadModel's player node that is currently playing
                _soundCollection[userInfo.0]![userInfo.1]!.stop(preview: userInfo.3);
            }
            
            //  reset the mixer node to volume prior to the fade
            _padMixerArray[userInfo.0][userInfo.1]?.volume = (_soundCollection[userInfo.0]![userInfo.1]?.volume)!;
            
            _fadeCountArray[userInfo.0][userInfo.1] = 0;
            _fadeScalarArray[userInfo.0][userInfo.1] = 1.0;
            
            timer.invalidate();
            
            _releaseTimerArray[userInfo.0][userInfo.1] = nil;
        }
        
        _fadeCountArray[userInfo.0][userInfo.1] += 1;
    }

    /** connect each pad in the pad array to a mixer node,
            and then connect each mixer node for each pad to a single mixer node */
    func connectPadToMixer(bank: Int, pad: Int)
    {
        if(_outputFormat.channelCount == 0 && _outputFormat.sampleRate == 0.0)
        {
            if(_debugFlag){ print("connectPadToMixer returned prematurely due to invalid _outputFormat");   }
            return;
        }
        // initialize pad's mixer node
        if(_padMixerArray[bank][pad] == nil){   _padMixerArray[bank][pad] = AVAudioMixerNode(); }
        
        _engine.attach(_padMixerArray[bank][pad]!)
        
        if(_soundCollection[bank]![pad] != nil)
        {
            // we need to connect both the player nodes and varispeed nodes to the sound graph
            //  with formats based upon the format of the file loaded into the player nodes
            let tempPadSampleRate = _soundCollection[bank]![pad]?.file.fileFormat.sampleRate;
            let tempFileChannelCount = _soundCollection[bank]![pad]?.file.fileFormat.channelCount
            
            for i in 0 ..< (_soundCollection[bank]![pad]?.playerNodeArrayCount)!
            {
                // attach and connect varispeed nodes to the pad mixer
                _engine.attach((_soundCollection[bank]![pad]?.varispeedNodeArray[i])!);
                _engine.attach((_soundCollection[bank]![pad]?.playerNodeArray[i])!);
                _engine.connect((_soundCollection[bank]![pad]?.varispeedNodeArray[i])!, to: _padMixerArray[bank][pad]!, format: AVAudioFormat(standardFormatWithSampleRate: tempPadSampleRate!, channels: tempFileChannelCount!));
                
                _engine.connect((_soundCollection[bank]![pad]?.playerNodeArray[i])!, to: (_soundCollection[bank]![pad]?.varispeedNodeArray[i])!, format: AVAudioFormat(standardFormatWithSampleRate: tempPadSampleRate!, channels: tempFileChannelCount!));
            }
        }
        
        _engine.connect(_padMixerArray[bank][pad]!, to: _engine.mainMixerNode, format: _outputFormat);
        
        installReadTapOnPadMixer(bank: bank, pad: pad);
    }