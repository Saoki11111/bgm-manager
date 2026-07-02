#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <sys/time.h>
#import <unistd.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSArray<NSDictionary *> *songs;
@property NSTask *mpvTask;
@property NSTimer *stopTimer;
@property NSTimer *refreshTimer;
@property NSDate *startedAt;
@property NSTimeInterval duration;
@property BOOL durationOverrideEnabled;
@property NSString *currentTitle;
@property BOOL paused;
@property NSDate *pausedAt;
@property NSTimeInterval accumulatedPausedDuration;
@property NSString *socketPath;
@property NSString *repositoryPath;
@property NSString *songsPath;
@property NSString *logPath;
@property NSTimeInterval playbackPosition;
@property NSTimeInterval mediaDuration;
@property BOOL hasPlaybackPosition;
@property NSMenuItem *nowPlayingItem;
@property NSMenuItem *remainingItem;
@property NSMenuItem *progressItem;
@property NSString *currentPlaybackPath;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.duration = 10800;
    self.durationOverrideEnabled = YES;
    self.socketPath = [NSString stringWithFormat:@"/tmp/bgm-manager-%d.sock", getuid()];
    self.repositoryPath = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"RepositoryPath"];
    self.songsPath = [self.repositoryPath stringByAppendingPathComponent:@"data/bgm-list.json"];
    self.logPath = [self defaultLogPath];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"♫";
    [self setupMainMenu];
    [self loadSongs];
    [self rebuildMenu];
    self.refreshTimer = [NSTimer timerWithTimeInterval:1 target:self selector:@selector(updateStatusTitle) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.refreshTimer forMode:NSRunLoopCommonModes];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopPlayback];
    [self.refreshTimer invalidate];
}

- (void)loadSongs {
    [self ensureSongsFile];
    NSData *data = [NSData dataWithContentsOfFile:self.songsPath];
    NSArray *decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![decoded isKindOfClass:[NSArray class]]) {
        self.songs = @[];
        return;
    }

    NSMutableArray<NSDictionary *> *validSongs = [NSMutableArray array];
    for (id item in decoded) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *url = item[@"url"];
        NSString *label = item[@"label"];
        if (![url isKindOfClass:[NSString class]] || url.length == 0) continue;
        if (![label isKindOfClass:[NSString class]] || label.length == 0) label = url;
        [validSongs addObject:@{@"label": label, @"url": url}];
    }
    self.songs = validSongs;
}

- (void)ensureSongsFile {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *directory = [self.songsPath stringByDeletingLastPathComponent];
    [fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    if (![fileManager fileExistsAtPath:self.songsPath]) {
        [@"[]\n" writeToFile:self.songsPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

- (NSString *)defaultLogPath {
    NSString *logs = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Logs/BGMManager"];
    [[NSFileManager defaultManager] createDirectoryAtPath:logs withIntermediateDirectories:YES attributes:nil error:nil];
    return [logs stringByAppendingPathComponent:@"mpv.log"];
}

- (void)removeOversizedPlaybackLog {
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.logPath error:nil];
    unsigned long long size = [attributes fileSize];
    if (size > 5 * 1024 * 1024) {
        [[NSFileManager defaultManager] removeItemAtPath:self.logPath error:nil];
    }
}

- (void)setupMainMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];

    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"]];
    [editMenu addItem:[[NSMenuItem alloc] initWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"]];

    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];
    NSApp.mainMenu = mainMenu;
}

- (NSMenuItem *)menuItemWithTitle:(NSString *)title symbol:(NSString *)symbol action:(SEL)action {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:title];
    return item;
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    self.nowPlayingItem = nil;
    self.remainingItem = nil;
    self.progressItem = nil;
    if (self.currentTitle) {
        self.nowPlayingItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        self.nowPlayingItem.enabled = NO;
        [menu addItem:self.nowPlayingItem];
        self.remainingItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        self.remainingItem.enabled = NO;
        [menu addItem:self.remainingItem];
        self.progressItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        self.progressItem.enabled = NO;
        [menu addItem:self.progressItem];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *omakase = [self menuItemWithTitle:@"Shuffle" symbol:@"shuffle" action:@selector(playOmakaseLoop)];
    omakase.target = self;
    omakase.enabled = self.songs.count > 0;
    [menu addItem:omakase];

    NSMenuItem *songs = [self menuItemWithTitle:@"Songs" symbol:@"music.note.list" action:nil];
    songs.submenu = [self songsMenu];
    songs.enabled = self.songs.count > 0;
    [menu addItem:songs];

    NSMenuItem *manageSongs = [self menuItemWithTitle:@"Edit Songs" symbol:@"slider.horizontal.3" action:nil];
    manageSongs.submenu = [self manageSongsMenu];
    manageSongs.enabled = self.songs.count > 0;
    [menu addItem:manageSongs];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *duration = [self menuItemWithTitle:[self durationMenuTitle] symbol:@"timer" action:nil];
    duration.submenu = [self durationMenu];
    [menu addItem:duration];

    NSMenuItem *pause = [self menuItemWithTitle:self.paused ? @"Play" : @"Pause"
                                         symbol:self.paused ? @"play.fill" : @"pause.fill"
                                         action:@selector(togglePause)];
    pause.target = self;
    pause.enabled = self.mpvTask.isRunning;
    [menu addItem:pause];

    NSMenuItem *stop = [self menuItemWithTitle:@"Stop" symbol:@"stop.fill" action:@selector(stopAction)];
    stop.target = self;
    stop.enabled = self.mpvTask.isRunning;
    [menu addItem:stop];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *add = [self menuItemWithTitle:@"Add URL..." symbol:@"plus" action:@selector(addURL)];
    add.target = self;
    [menu addItem:add];
    NSMenuItem *quit = [self menuItemWithTitle:@"Quit" symbol:@"power" action:@selector(quit)];
    quit.target = self;
    [menu addItem:quit];

    self.statusItem.menu = menu;
    [self updateStatusTitle];
}

- (void)updateStatusTitle {
    if (self.currentTitle) {
        [self refreshPlaybackProgress];
        self.statusItem.button.title = [self compactStatusTitle];
        [self updatePlaybackMenuItems];
    } else {
        self.statusItem.button.title = @"♫";
    }
}

- (void)updatePlaybackMenuItems {
    if (!self.currentTitle) return;
    NSTimeInterval elapsed = [self playbackElapsedDuration];
    NSString *position = self.hasPlaybackPosition ? [self formatTime:self.playbackPosition] : [self formatTime:elapsed];
    NSString *progress = [NSString stringWithFormat:@"Track: %@", position];
    if (self.mediaDuration > 0) {
        progress = [progress stringByAppendingFormat:@" / %@", [self formatTime:self.mediaDuration]];
    }
    self.nowPlayingItem.title = [NSString stringWithFormat:@"Playing: %@", [self displayTitle]];
    if (self.durationOverrideEnabled) {
        NSTimeInterval remaining = MAX(0, self.duration - elapsed);
        self.remainingItem.title = [NSString stringWithFormat:@"Time: %@ / %@  %ld%%  Left: %@", [self formatTime:elapsed], [self formatTime:self.duration], (long)[self progressPercent], [self formatTime:remaining]];
    } else {
        NSString *total = self.mediaDuration > 0 ? [self formatTime:self.mediaDuration] : @"--:--";
        self.remainingItem.title = [NSString stringWithFormat:@"Time: %@ / %@  %ld%%", position, total, (long)[self progressPercent]];
    }
    self.progressItem.title = progress;
}

- (NSMenu *)durationMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *autoDuration = [[NSMenuItem alloc] initWithTitle:@"Auto" action:@selector(clearDurationOverride) keyEquivalent:@""];
    autoDuration.target = self;
    autoDuration.state = self.durationOverrideEnabled ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:autoDuration];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray *values = @[@[@"1 hour", @3600], @[@"2 hours", @7200], @[@"3 hours", @10800]];
    for (NSArray *value in values) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:value[0] action:@selector(chooseDuration:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = value[1];
        item.state = self.durationOverrideEnabled && self.duration == [value[1] doubleValue] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    return menu;
}

- (NSMenu *)songsMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    if (self.songs.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No songs" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        return menu;
    }
    [self.songs enumerateObjectsUsingBlock:^(NSDictionary *song, NSUInteger index, BOOL *stop) {
        NSString *title = song[@"label"] ?: song[@"url"] ?: @"Untitled";
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(playSong:) keyEquivalent:@""];
        item.target = self;
        item.tag = index;
        item.state = [title isEqualToString:self.currentTitle] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }];
    return menu;
}

- (NSMenu *)manageSongsMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    if (self.songs.count == 0) {
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No songs" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        return menu;
    }
    [self.songs enumerateObjectsUsingBlock:^(NSDictionary *song, NSUInteger index, BOOL *stop) {
        NSString *title = song[@"label"] ?: song[@"url"] ?: @"Untitled";
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        NSMenu *submenu = [[NSMenu alloc] init];

        NSMenuItem *rename = [[NSMenuItem alloc] initWithTitle:@"Rename..." action:@selector(renameSong:) keyEquivalent:@""];
        rename.target = self;
        rename.tag = index;
        [submenu addItem:rename];

        NSMenuItem *delete = [[NSMenuItem alloc] initWithTitle:@"Delete..." action:@selector(deleteSong:) keyEquivalent:@""];
        delete.target = self;
        delete.tag = index;
        [submenu addItem:delete];

        item.submenu = submenu;
        [menu addItem:item];
    }];
    return menu;
}

- (void)playSong:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= self.songs.count) return;
    NSDictionary *song = self.songs[sender.tag];
    if (self.durationOverrideEnabled) {
        NSArray *arguments = @[
            song[@"url"],
            @"--loop-file=inf"
        ];
        [self startPlayback:song[@"label"] arguments:arguments];
    } else {
        [self startPlayback:song[@"label"] arguments:@[song[@"url"]]];
    }
}

- (void)playOmakaseLoop {
    if (self.songs.count == 0) return;
    NSUInteger index = arc4random_uniform((uint32_t)self.songs.count);
    NSDictionary *song = self.songs[index];
    [self startPlayback:song[@"label"] arguments:@[song[@"url"], @"--loop-file=inf"]];
}

- (void)startPlayback:(NSString *)title arguments:(NSArray<NSString *> *)arguments {
    [self stopPlayback];
    [[NSFileManager defaultManager] removeItemAtPath:self.socketPath error:nil];
    [self removeOversizedPlaybackLog];

    NSString *mpvPath = [self executablePathForName:@"mpv"];
    NSString *ytDlpPath = [self executablePathForName:@"yt-dlp"];
    if (!mpvPath || !ytDlpPath) {
        NSString *missing = !mpvPath ? @"mpv" : @"yt-dlp";
        [self showMessage:@"Can't Start Playback"
                     info:[NSString stringWithFormat:@"%@ was not found. Run: brew install mpv yt-dlp", missing]];
        return;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:mpvPath];
    NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    task.environment = environment;
    NSMutableArray *args = [@[
        @"--no-config", @"--no-video", @"--load-unsafe-playlists",
        @"--ytdl-format=ba[abr<128]/ba", @"--ytdl-raw-options=no-playlist=",
        @"--stream-lavf-o=reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5,reconnect_max_retries=3,reconnect_delay_total_max=15",
        @"--input-terminal=no", [NSString stringWithFormat:@"--input-ipc-server=%@", self.socketPath],
        @"--msg-level=all=warn", @"--force-window=no", @"--cache=yes", @"--cache-secs=120",
        [NSString stringWithFormat:@"--log-file=%@", self.logPath]
    ] mutableCopy];
    [args addObjectsFromArray:arguments];
    task.arguments = args;
    task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *finished) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf clearPlaybackState];
        });
    };

    NSError *error = nil;
    if ([task launchAndReturnError:&error]) {
        self.mpvTask = task;
        self.currentTitle = title;
        self.startedAt = [NSDate date];
        self.paused = NO;
        self.pausedAt = nil;
        self.accumulatedPausedDuration = 0;
        if (self.durationOverrideEnabled) [self scheduleStopTimer];
        [self rebuildMenu];
    } else {
        [self clearPlaybackState];
        [self showMessage:@"Can't Start Playback" info:error.localizedDescription ?: @"mpv could not be started."];
    }
}

- (void)scheduleStopTimer {
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    if (!self.durationOverrideEnabled) return;
    if (self.paused) return;
    NSTimeInterval elapsed = [self playbackElapsedDuration];
    NSTimeInterval remaining = MAX(1, self.duration - elapsed);
    self.stopTimer = [NSTimer timerWithTimeInterval:remaining target:self selector:@selector(stopAction) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.stopTimer forMode:NSRunLoopCommonModes];
}

- (void)togglePause {
    if (!self.mpvTask.isRunning) return;
    [self sendMPVCommand:@[@"cycle", @"pause"]];
    if (self.paused) {
        if (self.pausedAt) {
            self.accumulatedPausedDuration += [[NSDate date] timeIntervalSinceDate:self.pausedAt];
        }
        self.pausedAt = nil;
        self.paused = NO;
        if (self.durationOverrideEnabled) [self scheduleStopTimer];
    } else {
        self.paused = YES;
        self.pausedAt = [NSDate date];
        [self.stopTimer invalidate];
        self.stopTimer = nil;
    }
    [self rebuildMenu];
}

- (void)stopAction {
    [self stopPlayback];
}

- (void)stopPlayback {
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    NSTask *task = self.mpvTask;
    if (task.isRunning) {
        [self sendMPVCommand:@[@"quit"]];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (task.isRunning && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
    if (task.isRunning) {
        [task terminate];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.5];
        while (task.isRunning && [deadline timeIntervalSinceNow] > 0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
    }
    if (task.isRunning) {
        pid_t pid = task.processIdentifier;
        kill(pid, SIGKILL);
        [task waitUntilExit];
    }
    [self clearPlaybackState];
}

- (void)clearPlaybackState {
    self.mpvTask = nil;
    self.currentTitle = nil;
    self.startedAt = nil;
    self.paused = NO;
    self.pausedAt = nil;
    self.accumulatedPausedDuration = 0;
    self.playbackPosition = 0;
    self.mediaDuration = 0;
    self.hasPlaybackPosition = NO;
    self.currentPlaybackPath = nil;
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.socketPath error:nil];
    [self rebuildMenu];
}

- (void)chooseDuration:(NSMenuItem *)sender {
    NSTimeInterval selectedDuration = [sender.representedObject doubleValue];
    self.durationOverrideEnabled = YES;
    if (self.mpvTask.isRunning) {
        NSTimeInterval elapsed = [self playbackElapsedDuration];
        if (selectedDuration <= elapsed) {
            [self showMessage:@"Can't Shorten Timer" info:@"Select a duration longer than the elapsed playback time."];
            [self rebuildMenu];
            return;
        }
        self.duration = selectedDuration;
        [self sendMPVCommand:@[@"set_property", @"loop-file", @"inf"]];
        [self scheduleStopTimer];
    } else {
        self.duration = selectedDuration;
    }
    [self rebuildMenu];
}

- (void)addURL {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Add URL";
    alert.informativeText = @"Enter a YouTube URL. A copied URL is added here.";
    [alert addButtonWithTitle:@"Add"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    input.placeholderString = @"https://www.youtube.com/watch?v=...";
    NSString *clipboard = [[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString];
    clipboard = [clipboard stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([self isSupportedURL:clipboard]) input.stringValue = clipboard;
    alert.accessoryView = input;
    alert.window.initialFirstResponder = input;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *url = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [self addURLString:url];
}

- (void)addURLString:(NSString *)url {
    if (![self isSupportedURL:url]) {
        [self showMessage:@"Can't Add URL" info:@"Enter a youtube.com or youtu.be URL."];
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *title = [self titleForURL:url];
        if (title.length == 0) title = url;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendSongWithLabel:title url:url];
        });
    });
}

- (BOOL)isSupportedURL:(NSString *)url {
    if (url.length == 0) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithString:url];
    NSString *scheme = components.scheme.lowercaseString;
    NSString *host = components.host.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) &&
        ([host isEqualToString:@"youtube.com"] || [host isEqualToString:@"www.youtube.com"] || [host isEqualToString:@"youtu.be"]);
}

- (NSString *)titleForURL:(NSString *)url {
    NSString *ytDlpPath = [self executablePathForName:@"yt-dlp"];
    if (!ytDlpPath) return nil;
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:ytDlpPath];
    task.arguments = @[@"--no-playlist", @"--get-title", url];
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    NSError *error = nil;
    if (![task launchAndReturnError:&error]) return nil;
    [task waitUntilExit];
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSString *title = [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]].firstObject;
    return [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)executablePathForName:(NSString *)name {
    NSArray<NSString *> *directories = @[@"/opt/homebrew/bin", @"/usr/local/bin", @"/usr/bin", @"/bin"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *directory in directories) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        if ([fileManager isExecutableFileAtPath:path]) return path;
    }
    return nil;
}

- (void)appendSongWithLabel:(NSString *)label url:(NSString *)url {
    [self ensureSongsFile];
    NSMutableArray *items = [self.songs mutableCopy] ?: [NSMutableArray array];
    [items addObject:@{@"label": label, @"url": url}];
    if (![self saveSongs:items]) {
        [self showMessage:@"Can't Add URL" info:@"Could not save the song list."];
        return;
    }
    self.songs = items;
    [self rebuildMenu];
}

- (BOOL)saveSongs:(NSArray<NSDictionary *> *)songs {
    [self ensureSongsFile];
    NSData *data = [NSJSONSerialization dataWithJSONObject:songs options:NSJSONWritingPrettyPrinted error:nil];
    return data && [data writeToFile:self.songsPath atomically:YES];
}

- (void)renameSong:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= self.songs.count) return;
    NSDictionary *song = self.songs[sender.tag];
    NSString *currentLabel = song[@"label"] ?: song[@"url"] ?: @"";

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename";
    alert.informativeText = @"Enter a song name.";
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 420, 24)];
    input.stringValue = currentLabel;
    alert.accessoryView = input;
    alert.window.initialFirstResponder = input;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSString *label = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (label.length == 0) return;

    NSMutableArray *items = [self.songs mutableCopy];
    NSMutableDictionary *updated = [song mutableCopy];
    updated[@"label"] = label;
    items[sender.tag] = updated;

    if (![self saveSongs:items]) {
        [self showMessage:@"Can't Rename" info:@"Could not save the song list."];
        return;
    }
    self.songs = items;
    [self rebuildMenu];
}

- (void)deleteSong:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= self.songs.count) return;
    NSDictionary *song = self.songs[sender.tag];
    NSString *title = song[@"label"] ?: song[@"url"] ?: @"Untitled";

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Delete Song";
    alert.informativeText = [NSString stringWithFormat:@"Delete \"%@\" from the list? Music will keep playing.", title];
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSMutableArray *items = [self.songs mutableCopy];
    [items removeObjectAtIndex:sender.tag];
    if (![self saveSongs:items]) {
        [self showMessage:@"Can't Delete Song" info:@"Could not save the song list."];
        return;
    }
    self.songs = items;
    [self rebuildMenu];
}

- (void)clearDurationOverride {
    self.durationOverrideEnabled = NO;
    self.duration = 0;
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    if (self.mpvTask.isRunning) {
        [self sendMPVCommand:@[@"set_property", @"loop-file", @"no"]];
    }
    [self rebuildMenu];
}

- (void)showMessage:(NSString *)message info:(NSString *)info {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = message;
    alert.informativeText = info;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quit {
    [NSApp terminate:nil];
}

- (void)sendMPVCommand:(NSArray *)command {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"command": command} options:0 error:nil];
    if (!data) return;
    NSMutableData *message = [data mutableCopy];
    [message appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return;
    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, self.socketPath.fileSystemRepresentation, sizeof(address.sun_path));
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
        send(fd, message.bytes, message.length, 0);
    }
    close(fd);
}

- (void)refreshPlaybackProgress {
    NSNumber *position = [self mpvProperty:@"time-pos"];
    NSNumber *duration = [self mpvProperty:@"duration"];
    NSString *path = [self mpvStringProperty:@"path"];
    self.hasPlaybackPosition = position != nil;
    if (position) self.playbackPosition = position.doubleValue;
    if (duration) self.mediaDuration = duration.doubleValue;
    if (path.length > 0) self.currentPlaybackPath = path;
}

- (NSNumber *)mpvProperty:(NSString *)name {
    id value = [self mpvPropertyValue:name];
    return [value isKindOfClass:[NSNumber class]] ? value : nil;
}

- (NSString *)mpvStringProperty:(NSString *)name {
    id value = [self mpvPropertyValue:name];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

- (id)mpvPropertyValue:(NSString *)name {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"command": @[@"get_property", name]} options:0 error:nil];
    if (!data) return nil;
    NSMutableData *message = [data mutableCopy];
    [message appendData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd < 0) return nil;

    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 100000;
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    struct sockaddr_un address = {0};
    address.sun_family = AF_UNIX;
    strlcpy(address.sun_path, self.socketPath.fileSystemRepresentation, sizeof(address.sun_path));

    id result = nil;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) == 0) {
        send(fd, message.bytes, message.length, 0);
        char buffer[4096] = {0};
        ssize_t length = recv(fd, buffer, sizeof(buffer) - 1, 0);
        if (length > 0) {
            NSData *responseData = [NSData dataWithBytes:buffer length:(NSUInteger)length];
            NSDictionary *response = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
            result = response[@"data"];
        }
    }
    close(fd);
    return result;
}

- (NSString *)displayTitle {
    NSString *matched = [self labelForPlaybackPath:self.currentPlaybackPath];
    return matched.length > 0 ? matched : self.currentTitle;
}

- (NSString *)labelForPlaybackPath:(NSString *)path {
    if (path.length == 0) return nil;
    for (NSDictionary *song in self.songs) {
        NSString *url = song[@"url"];
        if ([url isKindOfClass:[NSString class]] && [url isEqualToString:path]) {
            NSString *label = song[@"label"];
            return [label isKindOfClass:[NSString class]] ? label : url;
        }
    }
    return nil;
}

- (NSString *)formatTime:(NSTimeInterval)value {
    NSInteger seconds = MAX(0, (NSInteger)value);
    NSInteger hours = seconds / 3600;
    NSInteger minutes = (seconds % 3600) / 60;
    NSInteger rest = seconds % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)rest];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)rest];
}

- (NSString *)formatDurationLabel:(NSTimeInterval)value {
    NSInteger seconds = MAX(0, (NSInteger)value);
    if (seconds % 3600 == 0) {
        NSInteger hours = seconds / 3600;
        return [NSString stringWithFormat:@"%ld hour%@", (long)hours, hours == 1 ? @"" : @"s"];
    }
    if (seconds % 60 == 0) return [NSString stringWithFormat:@"%ld min", (long)(seconds / 60)];
    return [self formatTime:value];
}

- (NSString *)durationMenuTitle {
    if (!self.durationOverrideEnabled) return @"Auto";
    return [self formatDurationLabel:self.duration];
}

- (NSTimeInterval)progressTotalDuration {
    if (self.durationOverrideEnabled) return self.duration;
    return self.mediaDuration > 0 ? self.mediaDuration : 0;
}

- (NSTimeInterval)progressElapsedDuration {
    if (self.durationOverrideEnabled) {
        return [self playbackElapsedDuration];
    }
    return self.hasPlaybackPosition ? self.playbackPosition : [self playbackElapsedDuration];
}

- (NSTimeInterval)playbackElapsedDuration {
    if (!self.startedAt) return 0;
    NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.startedAt] - self.accumulatedPausedDuration;
    if (self.pausedAt) {
        elapsed -= [[NSDate date] timeIntervalSinceDate:self.pausedAt];
    }
    return MAX(0, elapsed);
}

- (NSInteger)progressPercent {
    NSTimeInterval total = [self progressTotalDuration];
    if (total <= 0) return 0;
    NSTimeInterval elapsed = MAX(0, MIN([self progressElapsedDuration], total));
    return (NSInteger)llround((elapsed / total) * 100.0);
}

- (NSString *)progressGlyph {
    NSInteger percent = [self progressPercent];
    if (percent < 25) return @"◔";
    if (percent < 50) return @"◑";
    if (percent < 75) return @"◕";
    return @"●";
}

- (NSString *)compactStatusTitle {
    return [NSString stringWithFormat:@"♫ %@", [self progressGlyph]];
}

- (NSString *)compactTotalDurationLabel {
    NSTimeInterval total = [self progressTotalDuration];
    if (total <= 0) return @"";
    NSInteger seconds = MAX(0, (NSInteger)llround(total));
    NSInteger hours = seconds / 3600;
    NSInteger minutes = (seconds % 3600) / 60;
    if (hours > 0 && minutes > 0) return [NSString stringWithFormat:@"%ldh%ldm", (long)hours, (long)minutes];
    if (hours > 0) return [NSString stringWithFormat:@"%ldh", (long)hours];
    return [NSString stringWithFormat:@"%ldm", (long)MAX(1, minutes)];
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
