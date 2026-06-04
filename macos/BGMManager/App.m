#import <Cocoa/Cocoa.h>
#import <sys/socket.h>
#import <sys/un.h>
#import <unistd.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property NSStatusItem *statusItem;
@property NSArray<NSDictionary *> *songs;
@property NSTask *mpvTask;
@property NSTimer *stopTimer;
@property NSTimer *refreshTimer;
@property NSDate *startedAt;
@property NSTimeInterval duration;
@property NSString *currentTitle;
@property BOOL paused;
@property NSString *socketPath;
@property NSString *repositoryPath;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.duration = 3600;
    self.socketPath = [NSString stringWithFormat:@"/tmp/bgm-manager-%d.sock", getuid()];
    self.repositoryPath = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"RepositoryPath"];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"♫";
    [self loadSongs];
    [self rebuildMenu];
    self.refreshTimer = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(rebuildMenu) userInfo:nil repeats:YES];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self stopPlayback];
    [self.refreshTimer invalidate];
}

- (void)loadSongs {
    NSString *path = [self.repositoryPath stringByAppendingPathComponent:@"data/bgm-list.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSArray *decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    self.songs = [decoded isKindOfClass:[NSArray class]] ? decoded : @[];
}

- (void)rebuildMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    if (self.currentTitle) {
        NSTimeInterval remaining = MAX(0, self.duration - [[NSDate date] timeIntervalSinceDate:self.startedAt ?: [NSDate date]]);
        NSMenuItem *now = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"再生中: %@", self.currentTitle] action:nil keyEquivalent:@""];
        now.enabled = NO;
        [menu addItem:now];
        NSMenuItem *timer = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"残り %@", [self formatTime:remaining]] action:nil keyEquivalent:@""];
        timer.enabled = NO;
        [menu addItem:timer];
        [menu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *random = [[NSMenuItem alloc] initWithTitle:@"全曲ランダム再生" action:@selector(playRandom) keyEquivalent:@"r"];
    random.target = self;
    random.enabled = self.songs.count > 0;
    [menu addItem:random];
    if (self.songs.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        [self.songs enumerateObjectsUsingBlock:^(NSDictionary *song, NSUInteger index, BOOL *stop) {
            NSString *title = [NSString stringWithFormat:@"%lu. %@", (unsigned long)index + 1, song[@"label"] ?: @""];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(playSong:) keyEquivalent:@""];
            item.target = self;
            item.tag = index;
            item.state = [song[@"label"] isEqualToString:self.currentTitle] ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:item];
        }];
    }

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *duration = [[NSMenuItem alloc] initWithTitle:@"再生時間" action:nil keyEquivalent:@""];
    duration.submenu = [self durationMenu];
    [menu addItem:duration];

    NSMenuItem *pause = [[NSMenuItem alloc] initWithTitle:self.paused ? @"再開" : @"一時停止" action:@selector(togglePause) keyEquivalent:@"p"];
    pause.target = self;
    pause.enabled = self.mpvTask.isRunning;
    [menu addItem:pause];

    NSMenuItem *stop = [[NSMenuItem alloc] initWithTitle:@"停止" action:@selector(stopAction) keyEquivalent:@"."];
    stop.target = self;
    stop.enabled = self.mpvTask.isRunning;
    [menu addItem:stop];

    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *reload = [[NSMenuItem alloc] initWithTitle:@"曲リストを再読み込み" action:@selector(reloadList) keyEquivalent:@""];
    reload.target = self;
    [menu addItem:reload];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"BGM Managerを終了" action:@selector(quit) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];

    self.statusItem.menu = menu;
    if (self.currentTitle) {
        NSTimeInterval remaining = MAX(0, self.duration - [[NSDate date] timeIntervalSinceDate:self.startedAt ?: [NSDate date]]);
        self.statusItem.button.title = [NSString stringWithFormat:@"♫ %@", [self formatTime:remaining]];
    } else {
        self.statusItem.button.title = @"♫";
    }
}

- (NSMenu *)durationMenu {
    NSMenu *menu = [[NSMenu alloc] init];
    NSArray *values = @[@[@"30分", @1800], @[@"1時間", @3600], @[@"2時間", @7200]];
    for (NSArray *value in values) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:value[0] action:@selector(chooseDuration:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = value[1];
        item.state = self.duration == [value[1] doubleValue] ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:item];
    }
    return menu;
}

- (void)playSong:(NSMenuItem *)sender {
    if (sender.tag < 0 || sender.tag >= self.songs.count) return;
    NSDictionary *song = self.songs[sender.tag];
    [self startPlayback:song[@"label"] arguments:@[song[@"url"], @"--loop-file=inf"]];
}

- (void)playRandom {
    if (self.songs.count == 0) return;
    NSString *path = [NSString stringWithFormat:@"/tmp/bgm-manager-playlist-%d.txt", getuid()];
    NSMutableArray *urls = [NSMutableArray array];
    for (NSDictionary *song in self.songs) {
        if (song[@"url"]) [urls addObject:song[@"url"]];
    }
    NSString *contents = [[urls componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    [contents writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [self startPlayback:@"全曲ランダム" arguments:@[[NSString stringWithFormat:@"--playlist=%@", path], @"--shuffle", @"--loop-playlist=inf"]];
}

- (void)startPlayback:(NSString *)title arguments:(NSArray<NSString *> *)arguments {
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
        @"--msg-level=all=no", @"--force-window=no", @"--cache=yes", @"--cache-secs=10"
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
        [self scheduleStopTimer];
        [self rebuildMenu];
    } else {
        [self clearPlaybackState];
    }
}

- (void)scheduleStopTimer {
    [self.stopTimer invalidate];
    self.stopTimer = [NSTimer scheduledTimerWithTimeInterval:self.duration target:self selector:@selector(stopAction) userInfo:nil repeats:NO];
}

- (void)togglePause {
    if (!self.mpvTask.isRunning) return;
    [self sendMPVCommand:@[@"cycle", @"pause"]];
    self.paused = !self.paused;
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
        [task terminate];
        pid_t pid = task.processIdentifier;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            if (task.isRunning) kill(pid, SIGKILL);
        });
    }
    [self clearPlaybackState];
}

- (void)clearPlaybackState {
    self.mpvTask = nil;
    self.currentTitle = nil;
    self.startedAt = nil;
    self.paused = NO;
    [self.stopTimer invalidate];
    self.stopTimer = nil;
    [[NSFileManager defaultManager] removeItemAtPath:self.socketPath error:nil];
    [self rebuildMenu];
}

- (void)chooseDuration:(NSMenuItem *)sender {
    self.duration = [sender.representedObject doubleValue];
    if (self.mpvTask.isRunning) {
        self.startedAt = [NSDate date];
        [self scheduleStopTimer];
    }
    [self rebuildMenu];
}

- (void)reloadList {
    [self loadSongs];
    [self rebuildMenu];
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

- (NSString *)formatTime:(NSTimeInterval)value {
    NSInteger seconds = MAX(0, (NSInteger)value);
    NSInteger hours = seconds / 3600;
    NSInteger minutes = (seconds % 3600) / 60;
    NSInteger rest = seconds % 60;
    if (hours > 0) return [NSString stringWithFormat:@"%ld:%02ld:%02ld", (long)hours, (long)minutes, (long)rest];
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)minutes, (long)rest];
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
