//
//  MediaDownloads.x
//  NeoFreeBird
//

#import "HookHelpers.h"
#import <objc/runtime.h>

static NSURL* nfbLastCapturedVoiceURL = nil;

static BOOL IsVoiceMediaURL(NSURL* url) {
    if (url == nil) {
        return NO;
    }
    if ([url.path containsString:@"/decrypted-media-v2/"]) {
        return YES;
    }
    static NSSet* audioExtensions = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        audioExtensions = [NSSet setWithArray:@[@"m4a", @"aac", @"caf", @"wav", @"mp3"]];
    });
    return [audioExtensions containsObject:url.pathExtension.lowercaseString];
}

static void CaptureVoiceURL(NSURL* url, NSString* source) {
    if (![BHTSettings boolForKey:@"download_voice_messages"]) {
        return;
    }
    BOOL kept = IsVoiceMediaURL(url);
    NSLog(@"[NFB] voice capture (%@) %@: %@", source, kept ? @"kept" : @"ignored", url);
    if (kept) {
        nfbLastCapturedVoiceURL = url;
    }
}

%hook AVURLAsset
- (id)initWithURL:(NSURL*)url options:(NSDictionary*)options {
    CaptureVoiceURL(url, @"AVURLAsset");
    return %orig;
}
%end

// AVAudioPlayer is covered as well as AVURLAsset because the Chat stack no
// longer has to build an AVPlayer to play a short local note.
%hook AVAudioPlayer
- (id)initWithContentsOfURL:(NSURL*)url error:(NSError**)outError {
    CaptureVoiceURL(url, @"AVAudioPlayer");
    return %orig;
}
- (id)initWithContentsOfURL:(NSURL*)url
               fileTypeHint:(NSString*)utiString
                      error:(NSError**)outError {
    CaptureVoiceURL(url, @"AVAudioPlayer/fileTypeHint");
    return %orig;
}
%end

// DM voice notes are pre-decrypted straight to disk (Documents/dm/.../
// decrypted-media-v2/.../*.m4a), so the captured URL is normally a local
// file URL already -- just copy it out and hand it to the share sheet. The
// network branch is kept as a fallback in case that ever changes.
static void DownloadVoiceMessage(NSURL* sourceURL) {
    NSString* extension = sourceURL.pathExtension.length ? sourceURL.pathExtension : @"m4a";
    NSURL* destination = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
        URLByAppendingPathComponent:[NSString
                                         stringWithFormat:@"%@.%@", NSUUID.UUID.UUIDString, extension]];

    if (sourceURL.isFileURL) {
        NSError* copyError = nil;
        [[NSFileManager defaultManager] copyItemAtURL:sourceURL toURL:destination error:&copyError];
        if (copyError) {
            NSLog(@"[NFB] DownloadVoiceMessage copy failed: %@", copyError);
            return;
        }
        [BHTManager showSaveVC:destination];
        return;
    }

    TFNHUD* hud = [[objc_getClass("TFNHUD") alloc]
        initWithText:[[BHTBundle sharedBundle]
                          localizedStringForKey:@"DOWNLOAD_LIVE_ACTIVITY_DOWNLOADING"]];
    [hud show];
    NSURLSessionDownloadTask* task = [[NSURLSession sharedSession]
        downloadTaskWithURL:sourceURL
          completionHandler:^(NSURL* location, NSURLResponse* response, NSError* error) {
              dispatch_async(dispatch_get_main_queue(), ^{
                  [hud hide];
                  if (!location || error) {
                      return;
                  }
                  NSError* moveError = nil;
                  [[NSFileManager defaultManager] moveItemAtURL:location toURL:destination error:&moveError];
                  if (moveError) {
                      return;
                  }
                  [BHTManager showSaveVC:destination];
              });
          }];
    [task resume];
}

// MARK: - DM video download

// The DM UI is Swift now: media messages live in DMConversation.MessageAttachmentView,
// which hosts a shared TweetMediaAttachments media view exposing its models through
// -inlineMediaInfos. Collect the entities from whichever descendant carries them.
static NSArray* DMVideoEntities(UIView* attachmentView) {
    NSMutableArray* entities = [NSMutableArray new];

    EnumerateSubviewsRecursively(attachmentView, ^(UIView* view) {
        if (![view respondsToSelector:@selector(inlineMediaInfos)]) {
            return;
        }

        for (TFSTwitterMediaInfo* info in
             [(_TtC21TweetMediaAttachments14MultiMediaView*)view inlineMediaInfos]) {
            TFSTwitterEntityMedia* media = info.mediaEntity;
            if (media.videoInfo.variants.count > 0) {
                [entities addObject:media];
            }
        }
    });

    return [entities copy];
}

%hook _TtC14DMConversation21MessageAttachmentView
%property (nonatomic, strong) UIContextMenuInteraction* downloadMenuInteraction;
%property (nonatomic, strong) DownloadInlineButton* downloadHandler;
- (void)layoutSubviews {
    %orig;

    if ([BHTSettings boolForKey:@"download_videos"] && self.downloadMenuInteraction == nil) {
        self.downloadMenuInteraction = [[UIContextMenuInteraction alloc] initWithDelegate:self];
        [self addInteraction:self.downloadMenuInteraction];
    }
}
%new
- (UIContextMenuConfiguration*)contextMenuInteraction:(UIContextMenuInteraction*)interaction
                       configurationForMenuAtLocation:(CGPoint)location {
    NSArray* videoEntities = DMVideoEntities(self);
    if (videoEntities.count == 0) {
        return nil;
    }

    return [UIContextMenuConfiguration
        configurationWithIdentifier:nil
                    previewProvider:nil
                     actionProvider:^UIMenu* _Nullable(
                         NSArray<UIMenuElement*>* _Nonnull suggestedActions) {
                         UIAction* saveAction = [UIAction
                             actionWithTitle:
                                 [[BHTBundle sharedBundle]
                                     localizedTwitterStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                                       image:[UIImage systemImageNamed:@"square.and.arrow.down"]
                                  identifier:nil
                                     handler:^(__kindof UIAction* _Nonnull action) {
                                         if (self.downloadHandler == nil) {
                                             self.downloadHandler = [%c(DownloadInlineButton) new];
                                         }
                                         [self.downloadHandler
                                             presentDownloadOptionsForMediaEntities:videoEntities];
                                     }];
                         return [UIMenu menuWithTitle:@"" children:@[saveAction]];
                     }];
}
%end


// MARK: - Chat voice bubble
//
// The audio view sits inside MessageAttachmentView but carries its own gesture
// rather than sharing the video download menu above, so that a long press on a
// voice note wins over the stock chat context menu.

static const void* kVoiceDownloadLongPressKey = &kVoiceDownloadLongPressKey;

static UILongPressGestureRecognizer* VoiceDownloadLongPressRecognizer(UIView* view) {
    return objc_getAssociatedObject(view, kVoiceDownloadLongPressKey);
}

static void SetVoiceDownloadLongPressRecognizer(UIView* view,
                                                UILongPressGestureRecognizer* recognizer) {
    objc_setAssociatedObject(view, kVoiceDownloadLongPressKey, recognizer,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

%hook _TtC16ChatConversation26MessageAttachmentAudioView

- (void)layoutSubviews {
    %orig;

    if (![BHTSettings boolForKey:@"download_voice_messages"] ||
        VoiceDownloadLongPressRecognizer(self) != nil) {
        return;
    }

    UILongPressGestureRecognizer* longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self
                action:@selector(nfb_handleVoiceDownloadLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.numberOfTouchesRequired = 2;
    longPress.cancelsTouchesInView = NO;

    [self addGestureRecognizer:longPress];
    SetVoiceDownloadLongPressRecognizer(self, longPress);
}

// The view overrides -gestureRecognizerShouldBegin: for its own waveform pan
// gesture, and UIKit routes that override through for *every* recognizer
// attached to the view -- ours included. Without this passthrough the long
// press installs cleanly and then never begins.
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer*)gestureRecognizer {
    if (gestureRecognizer == VoiceDownloadLongPressRecognizer(self)) {
        return YES;
    }
    return %orig;
}

%new
- (void)nfb_handleVoiceDownloadLongPress:(UILongPressGestureRecognizer*)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) {
        return;
    }

    NSURL* voiceURL = nfbLastCapturedVoiceURL;
    if (voiceURL == nil) {
        return;
    }

    TFNActionItem* downloadItem = [objc_getClass("TFNActionItem")
        actionItemWithTitle:[[BHTBundle sharedBundle]
                                localizedStringForKey:@"DOWNLOAD_ACTIVITY_VIEW_LABEL"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         DownloadVoiceMessage(voiceURL);
                     }];

    TFNMenuSheetViewController* sheet = [[objc_getClass("TFNMenuSheetViewController") alloc]
        initWithActionItems:@[downloadItem]];

    [sheet tfnPresentedCustomPresentFromViewController:topMostController()
                                              animated:YES
                                            completion:nil];
}

%end

// MARK: - Upload custom voice

// Overwrites the recording at the attachment's existing file path, so the
// composer picks up the replacement without any model changes.
%hook T1MediaAttachmentsViewCell
%property (nonatomic, strong) UIButton* uploadButton;
- (void)updateCellElements {
    %orig;

    BOOL isVoiceRecording = [self.attachment isKindOfClass:%c(TTMAssetVoiceRecording)];

    if (isVoiceRecording && self.uploadButton == nil) {
        TFNButton* removeButton = [self valueForKey:@"_removeButton"];
        if (removeButton == nil) {
            return;
        }

        self.uploadButton = [UIButton buttonWithType:UIButtonTypeCustom];
        UIImageSymbolConfiguration* smallConfig =
            [UIImageSymbolConfiguration configurationWithScale:UIImageSymbolScaleSmall];
        UIImage* arrowUpImage = [UIImage systemImageNamed:@"arrow.up" withConfiguration:smallConfig];
        [self.uploadButton setImage:arrowUpImage forState:UIControlStateNormal];
        [self.uploadButton addTarget:self
                              action:@selector(handleUploadButton:)
                    forControlEvents:UIControlEventTouchUpInside];
        [self.uploadButton setTintColor:UIColor.labelColor];
        [self.uploadButton setBackgroundColor:[UIColor blackColor]];
        [self.uploadButton.layer setCornerRadius:29 / 2];
        [self.uploadButton setTranslatesAutoresizingMaskIntoConstraints:false];

        [self addSubview:self.uploadButton];
        [NSLayoutConstraint activateConstraints:@[
            [self.uploadButton.trailingAnchor constraintEqualToAnchor:removeButton.leadingAnchor
                                                             constant:-10],
            [self.uploadButton.topAnchor constraintEqualToAnchor:removeButton.topAnchor],
            [self.uploadButton.widthAnchor constraintEqualToConstant:29],
            [self.uploadButton.heightAnchor constraintEqualToConstant:29],
        ]];
    }

    self.uploadButton.hidden = !isVoiceRecording;
}
%new
- (void)handleUploadButton:(UIButton*)sender {
    UIImagePickerController* videoPicker = [[UIImagePickerController alloc] init];
    videoPicker.mediaTypes = @[(NSString*)kUTTypeMovie];
    videoPicker.delegate = self;

    [topMostController() presentViewController:videoPicker animated:YES completion:nil];
}
%new
- (void)imagePickerController:(UIImagePickerController*)picker
    didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id>*)info {
    NSURL* videoURL = info[UIImagePickerControllerMediaURL];
    TTMAssetVoiceRecording* attachment = self.attachment;
    NSURL* recorder_url = [NSURL fileURLWithPath:attachment.filePath];

    if (recorder_url != nil) {
        NSFileManager* fileManager = [NSFileManager defaultManager];

        NSError* error = nil;
        if ([fileManager fileExistsAtPath:[recorder_url path]]) {
            [fileManager removeItemAtURL:recorder_url error:&error];
            if (error) {
                NSLog(@"[BHTwitter] Error removing existing file: %@", error);
            }
        }

        [fileManager copyItemAtURL:videoURL toURL:recorder_url error:&error];
        if (error) {
            NSLog(@"[BHTwitter] Error copying file: %@", error);
        }
    }

    [picker dismissViewControllerAnimated:true completion:nil];
}
%new
- (void)imagePickerControllerDidCancel:(UIImagePickerController*)picker {
    [picker dismissViewControllerAnimated:true completion:nil];
}
%end

// MARK: - Save tweet as an image

%hook TTAStatusInlineShareButton
- (void)didLongPressActionButton:(UILongPressGestureRecognizer*)gestureRecognizer {
    if ([BHTSettings boolForKey:@"tweet_to_image"]) {
        if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {
            UIView* statusView = self.superview;
            while (statusView && ![statusView respondsToSelector:@selector(eventHandler)]) {
                statusView = statusView.superview;
            }

            UIView* tweetView = nil;
            id eventHandler = [(T1StandardStatusView*)statusView eventHandler];
            if ([eventHandler isKindOfClass:UIView.class]) {
                tweetView = eventHandler;
            }

            if (tweetView == nil) {
                UIView* ancestor = self.superview;
                while (ancestor && ![ancestor isKindOfClass:UITableViewCell.class] &&
                       ![ancestor isKindOfClass:UICollectionViewCell.class]) {
                    ancestor = ancestor.superview;
                }
                tweetView = ancestor;
            }

            if (tweetView == nil) {
                return %orig;
            }

            UIImage* tweetImage = imageFromView(tweetView);
            NSData* pngData = UIImagePNGRepresentation(tweetImage);
            NSURL* pngURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:[NSString
                                                stringWithFormat:@"%@.png", [[NSUUID UUID] UUIDString]]];
            [pngData writeToURL:pngURL atomically:YES];
            UIActivityViewController* acVC =
                [[UIActivityViewController alloc] initWithActivityItems:@[pngURL]
                                                  applicationActivities:nil];
            if (is_iPad()) {
                acVC.popoverPresentationController.sourceView = self;
                acVC.popoverPresentationController.sourceRect = self.frame;
            }
            [topMostController() presentViewController:acVC animated:true completion:nil];
            return;
        }
    }
    return %orig;
}
%end

// MARK: - Tweet video download

// _t1_actionItemsForStatus:... is a category method on UIViewController, so the
// hook has to land on the base class to cover every share/action sheet.
%hook UIViewController
- (NSArray*)_t1_actionItemsForStatus:(__unsafe_unretained id)status
                             account:(__unsafe_unretained id)account
                     shareableEntity:(__unsafe_unretained id)shareableEntity
                           entityURL:(__unsafe_unretained id)entityURL
                              source:(__unsafe_unretained id)source
                             options:(NSUInteger)options
                     scribeComponent:(__unsafe_unretained id)scribeComponent
                           doneBlock:(__unsafe_unretained id)doneBlock {
    NSArray* origItems = %orig;

    if (![BHTSettings boolForKey:@"download_videos"] ||
        ![status respondsToSelector:@selector(entities)]) {
        return origItems;
    }

    NSArray* mediaEntities = [[status entities] media];
    // A mixed photo/video tweet can place only its first photo in entities.
    // Prefer the complete extended media set when the model exposes it.
    @try {
        id extended = [status valueForKey:@"extendedEntities"];
        NSArray* complete = [extended respondsToSelector:@selector(media)] ? [extended media] :
                            ([extended isKindOfClass:NSArray.class] ? extended : nil);
        if (complete.count > mediaEntities.count) mediaEntities = complete;
    } @catch (__unused NSException* exception) {}
    BOOL hasVideo = NO;
    // mediaType 2 = GIF, 3 = video
    for (TFSTwitterEntityMedia* media in mediaEntities) {
        if ([media isKindOfClass:%c(TFSTwitterEntityMedia)] &&
            (media.mediaType == 2 || media.mediaType == 3)) {
            hasVideo = YES;
            break;
        }
    }
    if (!hasVideo) {
        return origItems;
    }

    static char downloaderKey;
    DownloadInlineButton* downloader = objc_getAssociatedObject(self, &downloaderKey);
    if (!downloader) {
        downloader = [%c(DownloadInlineButton) new];
        objc_setAssociatedObject(self, &downloaderKey, downloader, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    TFNActionItem* downloadItem = [%c(TFNActionItem)
        actionItemWithTitle:[[BHTBundle sharedBundle] localizedStringForKey:@"DOWNLOAD_VIDEOS_TITLE"]
                  imageName:@"arrow_down_circle_stroke"
                     action:^{
                         [downloader presentDownloadOptionsForMediaEntities:mediaEntities];
                     }];

    NSMutableArray* newItems = origItems ? [origItems mutableCopy] : [NSMutableArray array];
    NSUInteger insertIndex = newItems.count > 0 ? newItems.count - 1 : 0;
    [newItems insertObject:downloadItem atIndex:insertIndex];
    return newItems;
}
%end

// Restore the inline video action lost when the archived tweak was replaced.
@interface NFBVideoDownloadActionButton : UIButton
@property(nonatomic, weak) TTAStatusInlineActionsView* delegate;
@property(nonatomic, strong) id viewModel;
@property(nonatomic, strong) id buttonAnimator;
@property(nonatomic, assign) NSUInteger inlineActionType;
@property(nonatomic, assign) NSUInteger displayType;
@property(nonatomic, assign) UIEdgeInsets touchInsets;
@end

@implementation NFBVideoDownloadActionButton
+ (CGSize)buttonImageSizeUsingViewModel:(id)model options:(NSUInteger)options overrideButtonSize:(CGSize)size account:(id)account { return CGSizeZero; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.inlineActionType = 131;
        self.tintColor = [UIColor colorWithWhite:0.43 alpha:1.0];
        [self setImage:[UIImage systemImageNamed:@"arrow.down"] forState:UIControlStateNormal];
        [self addTarget:self action:@selector(nfb_downloadTapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (instancetype)initWithOptions:(NSUInteger)options overrideSize:(id)size account:(id)account { return [self initWithFrame:CGRectZero]; }
- (instancetype)initWithInlineActionType:(NSUInteger)type options:(NSUInteger)options overrideSize:(id)size account:(id)account { return [self initWithFrame:CGRectZero]; }
- (void)nfb_downloadTapped {
    id model = self.delegate.viewModel ?: self.viewModel;
    if (![model respondsToSelector:@selector(representedMediaEntities)]) return;
    NSArray* media = [model representedMediaEntities];
    if (![media isKindOfClass:NSArray.class] || media.count == 0) return;
    DownloadInlineButton* handler = objc_getAssociatedObject(self, @selector(nfb_downloadTapped));
    if (!handler) {
        handler = [DownloadInlineButton new];
        objc_setAssociatedObject(self, @selector(nfb_downloadTapped), handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [handler presentDownloadOptionsForMediaEntities:media];
}
- (void)statusDidUpdate:(id)status options:(NSUInteger)options displayTextOptions:(NSUInteger)textOptions animated:(BOOL)animated {}
- (void)statusDidUpdate:(id)status options:(NSUInteger)options displayTextOptions:(NSUInteger)textOptions animated:(BOOL)animated featureSwitches:(id)switches {}
- (id)_t1_imageNamed:(id)name fitSize:(CGSize)size fillColor:(id)fill { return nil; }
+ (id)_t1_imageNamed:(id)name fitSize:(CGSize)size fillColor:(id)fill { return nil; }
- (void)setTouchInsets:(UIEdgeInsets)insets { _touchInsets = insets; self.imageEdgeInsets = insets; }
#define NFB_INLINE_METRIC(name, value) - (typeof(value))name { return value; } + (typeof(value))name { return value; }
NFB_INLINE_METRIC(extraWidth, 40.0)
NFB_INLINE_METRIC(extraWidthWithStyle, 40.0)
NFB_INLINE_METRIC(trailingEdgeInset, 6.0)
NFB_INLINE_METRIC(visibility, (NSUInteger)1)
NFB_INLINE_METRIC(alternateInlineActionType, (NSUInteger)6)
NFB_INLINE_METRIC(touchInsetPriority, (NSUInteger)2)
NFB_INLINE_METRIC(shouldShowCount, NO)
NFB_INLINE_METRIC(horizontalLayoutOffset, 0.0)
#undef NFB_INLINE_METRIC
- (NSString*)actionSheetTitle { return @"Download"; }
@end
