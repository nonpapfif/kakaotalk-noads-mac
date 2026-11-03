#import "AppUpdater.h"
#import <CommonCrypto/CommonDigest.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString *const ReleasePrefix = @"https://github.com/nonpapfif/kakaotalk-noads-reconnect/releases/download/";
static NSString *const ExpectedIdentity = @"local.elsholtzia.KakaoTalkReconnectExperiment";
static IMP OriginalTerminate;

static NSString *HashFile(NSURL *url, NSError **error) {
    NSFileHandle *file = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!file) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    while (YES) {
        NSData *data = [file readDataUpToLength:1048576 error:error];
        if (!data) { [file closeFile]; return nil; }
        if (!data.length) break;
        CC_SHA256_Update(&context, data.bytes, (CC_LONG)data.length);
    }
    [file closeFile];
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(bytes, &context);
    NSMutableString *hash = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [hash appendFormat:@"%02x", bytes[i]];
    return hash;
}
static NSError *UpdateError(NSString *message) {
    return [NSError errorWithDomain:@"KakaoTalkUpdater" code:1
        userInfo:@{NSLocalizedDescriptionKey: message}];
}
static NSString *CurrentRelease(void) {
    return [NSBundle.mainBundle objectForInfoDictionaryKey:@"KakaoTalkPatchRelease"]
        ?: @"v26.9.0-reconnect.3";
}
static BOOL ValidTag(NSString *tag) {
    if (![tag isKindOfClass:NSString.class]) return NO;
    NSRegularExpression *pattern = [NSRegularExpression regularExpressionWithPattern:
        @"^v[0-9]+([.][0-9]+)*-reconnect[.][0-9]+$" options:0 error:nil];
    return [pattern firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)] != nil;
}
static BOOL RunCommand(NSString *path, NSArray<NSString *> *arguments, NSError **error) {
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = arguments;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = pipe;
    if (![task launchAndReturnError:error]) return NO;
    NSData *output = [pipe.fileHandleForReading readDataToEndOfFile];
    [task waitUntilExit];
    if (task.terminationStatus == 0) return YES;
    if (error) *error = UpdateError([[NSString alloc] initWithData:output
        encoding:NSUTF8StringEncoding] ?: @"Update validation failed.");
    return NO;
}

@interface KakaoTalkAppUpdater ()
@property(nonatomic, strong) NSMenuItem *item;
@property(nonatomic, strong) NSURLSession *session;
@property(nonatomic, strong) NSURL *root;
@property(nonatomic, strong) NSURL *readyFolder;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL helperLaunched;
@property(nonatomic) BOOL helperLaunching;
- (void)checkForUpdates:(id)sender;
- (void)terminateApplication:(id)sender;
@end

static void TerminateWithUpdate(id app, SEL selector, id sender) {
    (void)app; (void)selector;
    [[KakaoTalkAppUpdater sharedUpdater] terminateApplication:sender];
}

@implementation KakaoTalkAppUpdater
+ (instancetype)sharedUpdater {
    static KakaoTalkAppUpdater *updater;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ updater = [KakaoTalkAppUpdater new]; });
    return updater;
}
- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURL *cache = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
        inDomains:NSUserDomainMask].firstObject;
    self.root = [cache URLByAppendingPathComponent:@"KakaoTalkUpdates" isDirectory:YES];
    self.session = [NSURLSession sessionWithConfiguration:
        NSURLSessionConfiguration.ephemeralSessionConfiguration];
    NSDictionary *pending = [NSDictionary dictionaryWithContentsOfURL:
        [self.root URLByAppendingPathComponent:@"PendingUpdate.plist"] error:nil];
    NSString *path = pending[@"directory"];
    if ([path isKindOfClass:NSString.class] && [path hasPrefix:[self.root.path stringByAppendingString:@"/"]]) {
        NSURL *folder = [NSURL fileURLWithPath:path];
        NSData *data = [NSData dataWithContentsOfURL:[folder URLByAppendingPathComponent:@"Ready.json"]];
        NSDictionary *manifest = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([manifest isKindOfClass:NSDictionary.class] && ValidTag(manifest[@"release_tag"]) &&
            [manifest[@"release_tag"] compare:CurrentRelease() options:NSNumericSearch] == NSOrderedDescending)
            self.readyFolder = folder;
    }
    Method terminate = class_getInstanceMethod(NSApplication.class, @selector(terminate:));
    OriginalTerminate = method_setImplementation(terminate, (IMP)TerminateWithUpdate);
    return self;
}
- (void)attachToMenu:(NSMenu *)menu {
    if (![menu isKindOfClass:NSMenu.class]) return;
    for (NSMenuItem *item in menu.itemArray) {
        if ([item.identifier isEqualToString:@"KakaoTalkCheckForUpdates"]) {
            self.item = item;
            return;
        }
    }
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:self.readyFolder
        ? @"Restart to Update..." : @"Check for Updates..."
        action:@selector(checkForUpdates:) keyEquivalent:@""];
    item.identifier = @"KakaoTalkCheckForUpdates";
    item.target = self;
    [menu insertItem:item atIndex:MIN(1, menu.numberOfItems)];
    self.item = item;
}
- (void)showError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.busy = NO;
        self.item.title = self.readyFolder ? @"Restart to Update..." : @"Check for Updates...";
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"Update could not finish";
        alert.informativeText = error.localizedDescription;
        [alert runModal];
    });
}
- (void)showReady {
    self.item.title = @"Restart to Update...";
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"Update ready";
    alert.informativeText = @"The update has been downloaded and verified. It will be applied after KakaoTalk quits. Finish drafts before restarting. Existing chat data is kept.";
    [alert addButtonWithTitle:@"Restart Now"];
    [alert addButtonWithTitle:@"Later"];
    if ([alert runModal] == NSAlertFirstButtonReturn) [NSApp terminate:nil];
}
- (void)checkForUpdates:(id)sender {
    (void)sender;
    if (self.busy) return;
    if (self.readyFolder) { [self showReady]; return; }
    self.busy = YES;
    self.item.title = @"Checking for Updates...";
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:
        @"https://api.github.com/repos/nonpapfif/kakaotalk-noads-reconnect/releases?per_page=100"]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
    [request setValue:@"KakaoTalk-NoAds-Reconnect" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
    [[self.session dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            id releases = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            if (error || ![http isKindOfClass:NSHTTPURLResponse.class] || http.statusCode != 200 ||
                ![releases isKindOfClass:NSArray.class]) {
                [self showError:error ?: UpdateError(@"GitHub returned an invalid response.")]; return;
            }
            NSDictionary *latest = nil;
            NSString *tag = CurrentRelease();
            for (id release in releases) {
                if (![release isKindOfClass:NSDictionary.class] || [release[@"draft"] boolValue] ||
                    !ValidTag(release[@"tag_name"])) continue;
                if ([release[@"tag_name"] compare:tag options:NSNumericSearch] == NSOrderedDescending) {
                    latest = release; tag = release[@"tag_name"];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.busy = NO;
                self.item.title = @"Check for Updates...";
                NSAlert *alert = [NSAlert new];
                if (!latest) {
                    alert.messageText = @"You're up to date";
                    alert.informativeText = [@"Installed release: " stringByAppendingString:CurrentRelease()];
                    [alert runModal]; return;
                }
                alert.messageText = @"An update is available";
                alert.informativeText = [NSString stringWithFormat:
                    @"Installed: %@\nAvailable: %@\n\nDownload now and apply after KakaoTalk quits?", CurrentRelease(), tag];
                [alert addButtonWithTitle:@"Download Update"];
                [alert addButtonWithTitle:@"Later"];
                if ([alert runModal] == NSAlertFirstButtonReturn) [self downloadRelease:latest];
            });
        }] resume];
}
- (NSDictionary *)assetNamed:(NSString *)name release:(NSDictionary *)release {
    id assets = release[@"assets"];
    if (![assets isKindOfClass:NSArray.class]) return nil;
    NSString *prefix = [[ReleasePrefix stringByAppendingString:release[@"tag_name"]] stringByAppendingString:@"/"];
    for (id asset in assets) {
        if (![asset isKindOfClass:NSDictionary.class] || ![asset[@"name"] isEqual:name]) continue;
        NSString *link = asset[@"browser_download_url"];
        NSString *digest = asset[@"digest"];
        if ([link isKindOfClass:NSString.class] && [link isEqual:[prefix stringByAppendingString:name]] &&
            [digest isKindOfClass:NSString.class] && [digest hasPrefix:@"sha256:"] && digest.length == 71)
            return asset;
    }
    return nil;
}
- (void)downloadRelease:(NSDictionary *)release {
    NSDictionary *asset = [self assetNamed:@"Update.json" release:release];
    if (!asset) { [self showError:UpdateError(@"This release has no verified in-app update package. Use its installer instead.")]; return; }
    self.busy = YES;
    self.item.title = @"Downloading Update...";
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:asset[@"browser_download_url"]]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:60];
    [[self.session dataTaskWithRequest:request completionHandler:
        ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (error || ![http isKindOfClass:NSHTTPURLResponse.class] || http.statusCode != 200 || !data) {
                [self showError:error ?: UpdateError(@"The update manifest could not be downloaded.")]; return;
            }
            NSError *failure = nil;
            NSURL *folder = [self.root URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
            if (![[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES
                attributes:nil error:&failure]) { [self showError:failure]; return; }
            NSURL *manifestURL = [folder URLByAppendingPathComponent:@"Ready.json"];
            if (![data writeToURL:manifestURL options:NSDataWritingAtomic error:&failure] ||
                ![[@"sha256:" stringByAppendingString:HashFile(manifestURL, &failure) ?: @""] isEqual:asset[@"digest"]]) {
                [self showError:failure ?: UpdateError(@"Manifest checksum mismatch.")]; return;
            }
            id manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:&failure];
            if (![manifest isKindOfClass:NSDictionary.class] ||
                ![manifest[@"release_tag"] isEqual:release[@"tag_name"]] ||
                ![manifest[@"bundle_id"] isEqual:ExpectedIdentity] ||
                ![manifest[@"archive_name"] isKindOfClass:NSString.class] ||
                ![manifest[@"minimum_macos"] isKindOfClass:NSString.class]) {
                [self showError:UpdateError(@"Invalid update metadata.")]; return;
            }
            for (NSString *key in @[@"app_version", @"app_build", @"archive_sha256",
                                     @"executable_sha256", @"helper_sha256"]) {
                if (![manifest[key] isKindOfClass:NSString.class] || ![manifest[key] length]) {
                    [self showError:UpdateError(@"The update manifest is incomplete.")]; return;
                }
            }
            NSString *installedVersion = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
            NSString *installedBuild = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
            NSComparisonResult appOrder = [manifest[@"app_version"] compare:installedVersion options:NSNumericSearch];
            if (appOrder == NSOrderedAscending || (appOrder == NSOrderedSame &&
                [manifest[@"app_build"] compare:installedBuild options:NSNumericSearch] == NSOrderedAscending)) {
                [self showError:UpdateError(@"Refusing an older KakaoTalk version.")]; return;
            }
            NSOperatingSystemVersion version = NSProcessInfo.processInfo.operatingSystemVersion;
            NSString *os = [NSString stringWithFormat:@"%ld.%ld.%ld", version.majorVersion, version.minorVersion, version.patchVersion];
            if ([os compare:manifest[@"minimum_macos"] options:NSNumericSearch] == NSOrderedAscending) {
                [self showError:UpdateError(@"This update requires a newer macOS version.")]; return;
            }
            NSDictionary *archive = [self assetNamed:manifest[@"archive_name"] release:release];
            if (!archive || ![archive[@"digest"] isEqual:[@"sha256:" stringByAppendingString:manifest[@"archive_sha256"] ?: @""]]) {
                [self showError:UpdateError(@"The update archive is missing or its checksum is inconsistent.")]; return;
            }
            [self downloadArchive:archive manifest:manifest folder:folder];
        }] resume];
}
- (void)downloadArchive:(NSDictionary *)asset manifest:(NSDictionary *)manifest folder:(NSURL *)folder {
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:asset[@"browser_download_url"]]
        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:300];
    [[self.session downloadTaskWithRequest:request completionHandler:
        ^(NSURL *location, NSURLResponse *response, NSError *error) {
            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            if (error || !location || ![http isKindOfClass:NSHTTPURLResponse.class] || http.statusCode != 200) {
                [self showError:error ?: UpdateError(@"The update download failed.")]; return;
            }
            NSError *failure = nil;
            NSURL *archive = [folder URLByAppendingPathComponent:@"Payload.zip"];
            if (![[NSFileManager defaultManager] moveItemAtURL:location toURL:archive error:&failure] ||
                ![HashFile(archive, &failure) isEqual:manifest[@"archive_sha256"]]) {
                [self showError:failure ?: UpdateError(@"Archive checksum mismatch.")]; return;
            }
            if (!RunCommand(@"/usr/bin/ditto", @[@"-x", @"-k", archive.path, folder.path], &failure)) {
                [self showError:failure]; return;
            }
            NSURL *app = [folder URLByAppendingPathComponent:@"KakaoTalk.app"];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfURL:
                [app URLByAppendingPathComponent:@"Contents/Info.plist"] error:&failure];
            BOOL valid = [info[@"CFBundleIdentifier"] isEqual:ExpectedIdentity] &&
                [info[@"KakaoTalkPatchRelease"] isEqual:manifest[@"release_tag"]] &&
                [info[@"CFBundleShortVersionString"] isEqual:manifest[@"app_version"]] &&
                [info[@"CFBundleVersion"] isEqual:manifest[@"app_build"]];
            for (NSArray *pair in @[@[@"Contents/MacOS/KakaoTalk", @"executable_sha256"],
                                    @[@"Contents/Frameworks/SessionReconnect.dylib", @"helper_sha256"]]) {
                NSURL *file = [app URLByAppendingPathComponent:pair[0]];
                valid = valid && [file.URLByResolvingSymlinksInPath.path hasPrefix:
                    [app.path stringByAppendingString:@"/"]] &&
                    [HashFile(file, &failure) isEqual:manifest[pair[1]]];
            }
            if (!valid || !RunCommand(@"/usr/bin/codesign", @[@"--verify", @"--deep", @"--strict", app.path], &failure)) {
                [self showError:failure ?: UpdateError(@"The staged app does not match the update.")]; return;
            }
            NSDictionary *pending = @{@"directory": folder.path};
            if (![pending writeToURL:[self.root URLByAppendingPathComponent:@"PendingUpdate.plist"] error:&failure]) {
                [self showError:failure]; return;
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                self.readyFolder = folder;
                self.busy = NO;
                [self showReady];
            });
        }] resume];
}
- (void)terminateApplication:(id)sender {
    if (!self.readyFolder || self.helperLaunched) {
        ((void (*)(id, SEL, id))OriginalTerminate)(NSApp, @selector(terminate:), sender);
        return;
    }
    if (self.helperLaunching) return;
    self.helperLaunching = YES;
    NSURL *updater = [NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:
        @"Contents/Helpers/KakaoTalkUpdater.app"];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    configuration.createsNewApplicationInstance = YES;
    configuration.arguments = @[@"--parent-pid", [NSString stringWithFormat:@"%d", getpid()],
                                @"--staging", self.readyFolder.path];
    [NSWorkspace.sharedWorkspace openApplicationAtURL:updater configuration:configuration
        completionHandler:^(NSRunningApplication *app, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.helperLaunching = NO;
                if (!app || error) { [self showError:error ?: UpdateError(@"The updater could not start.")]; return; }
                self.helperLaunched = YES;
                ((void (*)(id, SEL, id))OriginalTerminate)(NSApp, @selector(terminate:), sender);
            });
        }];
}
@end
