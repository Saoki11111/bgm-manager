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
@property BOOL playlistMode;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.duration = 0;
    self.durationOverrideEnabled = NO;
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
    self.songs = [decoded isKindOfClass:[NSArray class]] ? decoded : @[];
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

    NSMenuItem *songs = [[NSMenuItem alloc] initWithTitle:@"曲を選ぶ" action:nil keyEquivalent:@""];
    songs.submenu = [self songsMenu];
    songs.enabled = self.songs.count > 0;
    [menu addItem:songs];

    NSMenuItem *manageSongs = [[NSMenuItem alloc] initWithTitle:@"曲を管理" action:nil keyEquivalent:@""];
    manageSongs.submenu = [self manageSongsMenu];
    manageSongs.enabled = self.songs.count > 0;
    [menu addItem:manageSongs];

    NSMenuItem *random = [[NSMenuItem alloc] initWithTitle:@"ランダム再生" action:@selector(playRandom) keyEquivalent:@"r"];
    random.target = self;
    random.enabled = self.songs.count > 0;
    [menu addItem:random];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *duration = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"再生時間: %@", [self durationMenuTitle]] action:nil keyEquivalent:@""];
    duration.submenu = [self durationMenu];
    [menu addItem:duration];

    NSMenuItem *pause = [[NSMenuItem alloc] initWithTitle:self.paused ? @"再開（一時停止から戻る）" : @"一時停止（位置を残す）" action:@selector(togglePause) keyEquivalent:@"p"];
    pause.target = self;
    pause.enabled = self.mpvTask.isRunning;
    [menu addItem:pause];

    NSMenuItem *previous = [[NSMenuItem alloc] initWithTitle:@"前の曲" action:@selector(previousTrack) keyEquivalent:@"["];
    previous.target = self;
    previous.enabled = self.mpvTask.isRunning && self.playlistMode;
    [menu addItem:previous];

    NSMenuItem *next = [[NSMenuItem alloc] initWithTitle:@"次の曲" action:@selector(nextTrack) keyEquivalent:@"]"];
    next.target = self;
    next.enabled = self.mpvTask.isRunning && self.playlistMode;
    [menu addItem:next];

    NSMenuItem *stop = [[NSMenuItem alloc] initWithTitle:@"停止（再生を終了）" action:@selector(stopAction) keyEquivalent:@"."];
    stop.target = self;
    stop.enabled = self.mpvTask.isRunning;
    [menu addItem:stop];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *add = [[NSMenuItem alloc] initWithTitle:@"URLを追加..." action:@selector(addURL) keyEquivalent:@"a"];
    add.target = self;
    [menu addItem:add];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"BGM Managerを終了" action:@selector(quit) keyEquivalent:@"q"];
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
    NSString *progress = [NSString stringWithFormat:@"曲位置: %@", position];
    if (self.mediaDuration > 0) {
        progress = [progress stringByAppendingFormat:@" / %@", [self formatTime:self.mediaDuration]];
    }
    self.nowPlayingItem.title = [NSString stringWithFormat:@"再生中: %@", [self displayTitle]];
    if (self.durationOverrideEnabled) {
        NSTimeInterval remaining = MAX(0, self.duration - elapsed);
        self.remainingItem.title = [NSString stringWithFormat:@"進捗: %@ / %@  %ld%%  残り %@", [self formatTime:elapsed], [self formatTime:self.duration], (long)[self progressPercent], [self formatTime:remaining]];
    } else {
        NSString *total = self.mediaDuration > 0 ? [self formatTime:self.mediaDuration] : @"--:--";
        self.remainingItem.title = [NSString stringWithFormat:@"進捗: %@ / %@  %ld%%", position, total, (long)[self progressPercent]];
    }
    self.progressItem.title = progress;
}

- (NSMenu *)durationMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSMenuItem *autoDuration = [[NSMenuItem alloc] initWithTitle:@"自動（曲の長さ）" action:@selector(clearDurationOverride) keyEquivalent:@""];
    autoDuration.target = self;
    autoDuration.state = self.durationOverrideEnabled ? NSControlStateValueOff : NSControlStateValueOn;
    [menu addItem:autoDuration];
    [menu addItem:[NSMenuItem separatorItem]];

    NSArray *values = @[@[@"30分", @1800], @[@"1時間", @3600], @[@"2時間", @7200], @[@"3時間", @10800]];
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
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"曲がありません" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        return menu;
    }
    [self.songs enumerateObjectsUsingBlock:^(NSDictionary *song, NSUInteger index, BOOL *stop) {
        NSString *title = song[@"label"] ?: song[@"url"] ?: @"無題";
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
        NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"曲がありません" action:nil keyEquivalent:@""];
        empty.enabled = NO;
        [menu addItem:empty];
        return menu;
    }
    [self.songs enumerateObjectsUsingBlock:^(NSDictionary *song, NSUInteger index, BOOL *stop) {
        NSString *title = song[@"label"] ?: song[@"url"] ?: @"無題";
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
        NSMenu *submenu = [[NSMenu alloc] init];

        NSMenuItem *rename = [[NSMenuItem alloc] initWithTitle:@"表示名を変更..." action:@selector(renameSong:) keyEquivalent:@""];
        rename.target = self;
        rename.tag = index;
        [submenu addItem:rename];

        NSMenuItem *delete = [[NSMenuItem alloc] initWithTitle:@"削除..." action:@selector(deleteSong:) keyEquivalent:@""];
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
        [self startPlayback:song[@"label"] arguments:arguments playlistMode:NO];
    } else {
        [self startPlayback:song[@"label"] arguments:@[song[@"url"]]];
    }
}

- (void)playRandom {
    if (self.songs.count == 0) return;
    NSString *path = [self writePlaylistFile];
    NSMutableArray *arguments = [@[[NSString stringWithFormat:@"--playlist=%@", path], @"--shuffle"] mutableCopy];
    if (self.durationOverrideEnabled) [arguments addObject:@"--loop-playlist=inf"];
    [self startPlayback:@"ランダム再生" arguments:arguments playlistMode:YES];
}

- (NSString *)writePlaylistFile {
    NSString *path = [NSString stringWithFormat:@"/tmp/bgm-manager-playlist-%d.txt", getuid()];
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *song in self.songs) {
        if (song[@"url"]) [urls addObject:song[@"url"]];
    }
    NSString *contents = [[urls componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    return path;
}

- (void)startPlayback:(NSString *)title arguments:(NSArray<NSString *> *)arguments {
    [self startPlayback:title arguments:arguments playlistMode:NO];
}

- (void)startPlayback:(NSString *)title arguments:(NSArray<NSString *> *)arguments playlistMode:(BOOL)playlistMode {
    [self stopPlayback];
    [[NSFileManager defaultManager] removeItemAtPath:self.socketPath error:nil];

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/opt/homebrew/bin/mpv"];
    NSMutableDictionary *environment = [[[NSProcessInfo processInfo] environment] mutableCopy];
    environment[@"PATH"] = @"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin";
    task.environment = environment;
    NSMutableArray *args = [@[
        @"--no-config", @"--no-video", @"--load-unsafe-playlists",
        @"--ytdl-format=ba[abr<128]/ba", @"--ytdl-raw-options=no-playlist=",
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
        self.playlistMode = playlistMode;
        self.startedAt = [NSDate date];
        self.paused = NO;
        self.pausedAt = nil;
        self.accumulatedPausedDuration = 0;
        if (self.durationOverrideEnabled) [self scheduleStopTimer];
        [self rebuildMenu];
    } else {
        [self clearPlaybackState];
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

- (void)nextTrack {
    if (!self.mpvTask.isRunning || !self.playlistMode) return;
    [self sendMPVCommand:@[@"playlist-next", @"force"]];
    [self resetPlaybackTimingAfterTrackChange];
}

- (void)previousTrack {
    if (!self.mpvTask.isRunning || !self.playlistMode) return;
    [self sendMPVCommand:@[@"playlist-prev", @"force"]];
    [self resetPlaybackTimingAfterTrackChange];
}

- (void)resetPlaybackTimingAfterTrackChange {
    self.startedAt = [NSDate date];
    self.pausedAt = self.paused ? [NSDate date] : nil;
    self.accumulatedPausedDuration = 0;
    self.playbackPosition = 0;
    self.mediaDuration = 0;
    self.hasPlaybackPosition = NO;
    self.currentPlaybackPath = nil;
    if (self.durationOverrideEnabled) [self scheduleStopTimer];
    [self refreshPlaybackProgress];
    [self updateStatusTitle];
    [self updatePlaybackMenuItems];
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
    self.playlistMode = NO;
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.socketPath error:nil];
    [self rebuildMenu];
}

- (void)chooseDuration:(NSMenuItem *)sender {
    NSTimeInterval selectedDuration = [sender.representedObject doubleValue];
    self.durationOverrideEnabled = YES;
    if (self.mpvTask.isRunning) {
        self.startedAt = [NSDate date];
        self.pausedAt = self.paused ? [NSDate date] : nil;
        self.accumulatedPausedDuration = 0;
        self.duration = selectedDuration;
        if (self.playlistMode) {
            [self sendMPVCommand:@[@"set_property", @"loop-playlist", @"inf"]];
        } else {
            [self sendMPVCommand:@[@"set_property", @"loop-file", @"inf"]];
        }
        [self scheduleStopTimer];
    } else {
        self.duration = selectedDuration;
    }
    [self rebuildMenu];
}

- (void)addURL {
    [NSApp activateIgnoringOtherApps:YES];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"URLを追加";
    alert.informativeText = @"YouTube URLを入力してください。クリップボードにURLがあれば自動で入れます。";
    [alert addButtonWithTitle:@"追加"];
    [alert addButtonWithTitle:@"キャンセル"];

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
        [self showMessage:@"URLを追加できません" info:@"http://、https://、youtube.com、youtu.be のURLを入力してください。"];
        return;
    }

    NSString *title = [self titleForURL:url];
    if (title.length == 0) title = url;
    [self appendSongWithLabel:title url:url];
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
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/opt/homebrew/bin/yt-dlp"];
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

- (void)appendSongWithLabel:(NSString *)label url:(NSString *)url {
    [self ensureSongsFile];
    NSMutableArray *items = [self.songs mutableCopy] ?: [NSMutableArray array];
    [items addObject:@{@"label": label, @"url": url}];
    if (![self saveSongs:items]) {
        [self showMessage:@"URLを追加できません" info:@"曲リストファイルへの書き込みに失敗しました。"];
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
    alert.messageText = @"表示名を変更";
    alert.informativeText = @"メニューに表示する曲名を入力してください。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"キャンセル"];

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
        [self showMessage:@"表示名を変更できません" info:@"曲リストファイルへの書き込みに失敗しました。"];
        return;
    }
    self.songs = items;
    [self rebuildMenu];
}

- (void)deleteSong:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= self.songs.count) return;
    NSDictionary *song = self.songs[sender.tag];
    NSString *title = song[@"label"] ?: song[@"url"] ?: @"無題";

    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"曲を削除";
    alert.informativeText = [NSString stringWithFormat:@"「%@」を曲リストから削除します。再生中の音は停止しません。", title];
    [alert addButtonWithTitle:@"削除"];
    [alert addButtonWithTitle:@"キャンセル"];
    alert.alertStyle = NSAlertStyleWarning;

    if ([alert runModal] != NSAlertFirstButtonReturn) return;

    NSMutableArray *items = [self.songs mutableCopy];
    [items removeObjectAtIndex:sender.tag];
    if (![self saveSongs:items]) {
        [self showMessage:@"曲を削除できません" info:@"曲リストファイルへの書き込みに失敗しました。"];
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
        [self sendMPVCommand:@[@"set_property", @"loop-playlist", @"no"]];
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
    if (seconds % 3600 == 0) return [NSString stringWithFormat:@"%ld時間", (long)(seconds / 3600)];
    if (seconds % 60 == 0) return [NSString stringWithFormat:@"%ld分", (long)(seconds / 60)];
    return [self formatTime:value];
}

- (NSString *)durationMenuTitle {
    if (!self.durationOverrideEnabled) return @"自動（曲の長さ）";
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
