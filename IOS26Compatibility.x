#import <UIKit/UIKit.h>

static BOOL BHTIsIOS26OrNewer(void) {
    if (@available(iOS 26.0, *)) {
        return YES;
    }
    return NO;
}

static void BHTDisableTableViewPrefetching(UITableView *tableView) {
    if (!BHTIsIOS26OrNewer()) {
        return;
    }

    if ([tableView respondsToSelector:@selector(setPrefetchingEnabled:)]) {
        tableView.prefetchingEnabled = NO;
    }
}

%hook UITableView

- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    UITableView *tableView = %orig;
    BHTDisableTableViewPrefetching(tableView);
    return tableView;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    UITableView *tableView = %orig;
    BHTDisableTableViewPrefetching(tableView);
    return tableView;
}

- (void)setPrefetchingEnabled:(BOOL)enabled {
    if (BHTIsIOS26OrNewer()) {
        %orig(NO);
        return;
    }

    %orig(enabled);
}

%end
