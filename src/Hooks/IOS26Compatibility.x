//
//  IOS26Compatibility.x
//  NeoFreeBird
//
//  Twitter's table-view prefetch path can race reused timeline cells on iOS 26.
//  The previous 11.98 compatibility build was stable with prefetching disabled,
//  so keep that protection for the v7 build without affecting older systems.
//

#import <UIKit/UIKit.h>

static BOOL NFBIsIOS26OrNewer(void) {
    if (@available(iOS 26.0, *)) {
        return YES;
    }
    return NO;
}

static void NFBDisableTableViewPrefetching(UITableView* tableView) {
    if (!NFBIsIOS26OrNewer()) {
        return;
    }

    if ([tableView respondsToSelector:@selector(setPrefetchingEnabled:)]) {
        tableView.prefetchingEnabled = NO;
    }
}

%hook UITableView

- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    UITableView* tableView = %orig;
    NFBDisableTableViewPrefetching(tableView);
    return tableView;
}

- (instancetype)initWithCoder:(NSCoder*)coder {
    UITableView* tableView = %orig;
    NFBDisableTableViewPrefetching(tableView);
    return tableView;
}

- (void)setPrefetchingEnabled:(BOOL)enabled {
    if (NFBIsIOS26OrNewer()) {
        %orig(NO);
        return;
    }

    %orig(enabled);
}

%end
