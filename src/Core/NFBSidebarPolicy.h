#import <Foundation/Foundation.h>

// Stable 11.98 panel identities, not translated row titles.
FOUNDATION_EXPORT NSString *NFBSidebarPreferenceForPanel(long long panelID);
FOUNDATION_EXPORT NSString *NFBSidebarPreferenceForFeature(NSString *feature);
FOUNDATION_EXPORT NSArray *NFBSidebarClaimPanels(NSArray *visible, NSArray<NSNumber *> *hidden);
