#import <Foundation/Foundation.h>
#import "Core/NFBSidebarPolicy.h"

int main(void) {
    @autoreleasepool {
        NSCAssert([NFBSidebarPreferenceForPanel(18) isEqual:@"hide_jobs_sidebar"], @"Jobs panel");
        NSCAssert([NFBSidebarPreferenceForPanel(19) isEqual:@"hide_money_sidebar"], @"Money panel");
        NSCAssert([NFBSidebarPreferenceForPanel(22) isEqual:@"hide_news_sidebar"], @"News panel");
        NSCAssert(!NFBSidebarPreferenceForPanel(1), @"Do not hide Home");
        NSCAssert([NFBSidebarPreferenceForFeature(@"ai_trends_ios_enable_news_tab") isEqual:@"hide_news_sidebar"], @"News gate");
        for (NSString *key in @[@"recruiting_global_jobs_hub_enabled", @"recruiting_jetfuel_jobs_hub_enabled"]) {
            NSCAssert([NFBSidebarPreferenceForFeature(key) isEqual:@"hide_jobs_sidebar"], @"Both Jobs gates");
        }
        NSCAssert(!NFBSidebarPreferenceForFeature(@"communities_enable_explore_tab"), @"Other gates unchanged");
        NSCAssert(!NFBSidebarPreferenceForFeature(nil), @"Unknown gate unchanged");
        NSCAssert(!NFBSidebarPreferenceForPanel(16), @"Do not hide Media using a newer app's Jobs ID");
        NSCAssert(!NFBSidebarPreferenceForPanel(20), @"Do not hide offline cache using a newer app's News ID");
        NSArray *original = @[@1, @2, @18];
        NSArray *result = NFBSidebarClaimPanels(original, @[@18, @19, @22, @22]);
        NSCAssert([result isEqual:(@[@1, @2, @18, @19, @22])], @"Claim all hidden panels without duplicates");
        NSCAssert([original isEqual:(@[@1, @2, @18])], @"Do not mutate actual navigation");
        NSCAssert([NFBSidebarClaimPanels(nil, @[@18, @19, @22]) isEqual:(@[@18, @19, @22])], @"Empty navigation supported");
        NSCAssert([NFBSidebarClaimPanels(original, @[]) isEqual:original], @"Unhide is reversible");
        puts("PASS: Money/News/Jobs identity, feature gates, no duplicates, nil input, reversible navigation");
    }
}
