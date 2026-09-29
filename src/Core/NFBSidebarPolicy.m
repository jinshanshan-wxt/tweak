#import "NFBSidebarPolicy.h"

NSString *NFBSidebarPreferenceForPanel(long long panelID) {
    switch (panelID) {
        case 18: return @"hide_jobs_sidebar";
        case 19: return @"hide_money_sidebar";
        case 22: return @"hide_news_sidebar";
        default: return nil;
    }
}

NSString *NFBSidebarPreferenceForFeature(NSString *feature) {
    if ([feature isEqualToString:@"ai_trends_ios_enable_news_tab"]) return @"hide_news_sidebar";
    if ([feature isEqualToString:@"recruiting_global_jobs_hub_enabled"] ||
        [feature isEqualToString:@"recruiting_jetfuel_jobs_hub_enabled"]) return @"hide_jobs_sidebar";
    return nil;
}

NSArray *NFBSidebarClaimPanels(NSArray *visible, NSArray<NSNumber *> *hidden) {
    NSMutableArray *result = [visible isKindOfClass:NSArray.class] ? [visible mutableCopy] : [NSMutableArray array];
    for (NSNumber *panel in hidden) {
        // Claiming an ID hides the drawer row; removing it would add the row.
        if (![result containsObject:panel]) [result addObject:panel];
    }
    return result;
}
