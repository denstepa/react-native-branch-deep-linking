#import "RNBranch.h"
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTLog.h>
#import "BranchLinkProperties+RNBranch.h"
#import "BranchUniversalObject+RNBranch.h"

static NSDictionary *initSessionWithLaunchOptionsResult;
static NSURL *sourceUrl;
static Branch *branchInstance;

static NSString * const initSessionWithLaunchOptionsFinishedEventName = @"initSessionWithLaunchOptionsFinished";
static NSString * const IdentFieldName = @"ident";

// These are only really exposed to the JS layer, so keep them internal for now.
static NSString * const RNBranchErrorDomain = @"RNBranchErrorDomain";
static NSInteger const RNBranchUniversalObjectNotFoundError = 1;

#pragma mark - Private RNBranch declarations

@interface RNBranch()
@property (nonatomic, readonly) UIViewController *currentViewController;
@property (nonatomic) NSMutableDictionary<NSString *, BranchUniversalObject *> *universalObjectMap;
@end

#pragma mark - RNBranch implementation

@implementation RNBranch

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

#pragma mark - Class methods

+ (void)useTestInstance {
    branchInstance = [Branch getTestInstance];
}

//Called by AppDelegate.m -- stores initSession result in static variables and raises initSessionFinished event that's captured by the RNBranch instance to emit it to React Native
+ (void)initSessionWithLaunchOptions:(NSDictionary *)launchOptions isReferrable:(BOOL)isReferrable {
    sourceUrl = launchOptions[UIApplicationLaunchOptionsURLKey];

    if (!branchInstance) {
        branchInstance = [Branch getInstance];
    }
    [branchInstance initSessionWithLaunchOptions:launchOptions isReferrable:isReferrable andRegisterDeepLinkHandler:^(NSDictionary *params, NSError *error) {
        NSString *errorMessage = error.localizedDescription;

        initSessionWithLaunchOptionsResult = @{
                                               @"params": params && params[@"~id"] ? params : [NSNull null],
                                               @"error": errorMessage ?: [NSNull null],
                                               @"uri": sourceUrl.absoluteString ?: [NSNull null]
                                               };

        [[NSNotificationCenter defaultCenter] postNotificationName:initSessionWithLaunchOptionsFinishedEventName object:initSessionWithLaunchOptionsResult];
    }];
}

+ (BOOL)handleDeepLink:(NSURL *)url {
    sourceUrl = url;
    BOOL handled = [branchInstance handleDeepLink:url];
    return handled;
}

+ (BOOL)continueUserActivity:(NSUserActivity *)userActivity {
    sourceUrl = userActivity.webpageURL;
    return [branchInstance continueUserActivity:userActivity];
}

#pragma mark - Object lifecycle

- (instancetype)init {
    self = [super init];

    if (self) {
        _universalObjectMap = [NSMutableDictionary dictionary];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onInitSessionFinished:) name:initSessionWithLaunchOptionsFinishedEventName object:nil];
    }

    return self;
}

- (void) dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Utility methods

- (UIViewController *)currentViewController
{
    UIViewController *current = [UIApplication sharedApplication].keyWindow.rootViewController;
    while (current.presentedViewController && ![current.presentedViewController isKindOfClass:UIAlertController.class]) {
        current = current.presentedViewController;
    }
    return current;
}

- (void) onInitSessionFinished:(NSNotification*) notification {
    id notificationObject = notification.object;

    // If there is an error, fire error event
    if (notificationObject[@"error"] != [NSNull null]) {
        [self.bridge.eventDispatcher sendAppEventWithName:@"RNBranch.initSessionError" body:notificationObject];
    }

    // otherwise notify the session is finished
    else {
        [self.bridge.eventDispatcher sendAppEventWithName:@"RNBranch.initSessionSuccess" body:notificationObject];
    }
}

- (BranchLinkProperties*) createLinkProperties:(NSDictionary *)linkPropertiesMap withControlParams:(NSDictionary *)controlParamsMap
{
    BranchLinkProperties *linkProperties = [[BranchLinkProperties alloc] initWithMap:linkPropertiesMap];

    linkProperties.controlParams = controlParamsMap;
    return linkProperties;
}

- (BranchUniversalObject *)findUniversalObjectWithIdent:(NSString *)ident rejecter:(RCTPromiseRejectBlock)reject
{
    BranchUniversalObject *universalObject = self.universalObjectMap[ident];

    // This is extremely unlikely and amounts to a logic error.
    if (!universalObject) {
        NSString *errorMessage = [NSString stringWithFormat:@"BranchUniversalObject for ident %@ not found. Do not reuse a BUO after calling release() in JS. Create a new instance instead.", ident];

        NSError *error = [NSError errorWithDomain:RNBranchErrorDomain
                                             code:RNBranchUniversalObjectNotFoundError
                                         userInfo:@{IdentFieldName : ident,
                                                    NSLocalizedDescriptionKey: errorMessage
                                                    }];
        
        RCTLogError(@"%@", error.localizedDescription);

        reject(@"RNBranch::Error", errorMessage, error);
    }
    
    return universalObject;
}

#pragma mark - Methods exported to React Native

RCT_EXPORT_METHOD(
                  redeemInitSessionResult:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject
                  ) {
    resolve(initSessionWithLaunchOptionsResult ? initSessionWithLaunchOptionsResult : [NSNull null]);
    initSessionWithLaunchOptionsResult = [NSNull null];
    sourceUrl = nil;
}

RCT_EXPORT_METHOD(
                  setDebug
                  ) {
    [branchInstance setDebug];
}

RCT_EXPORT_METHOD(
                  getLatestReferringParams:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject
                  ) {
    resolve([branchInstance getLatestReferringParams]);
}

RCT_EXPORT_METHOD(
                  getFirstReferringParams:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject
                  ) {
    resolve([branchInstance getFirstReferringParams]);
}

RCT_EXPORT_METHOD(
                  setIdentity:(NSString *)identity
                  ) {
    [branchInstance setIdentity:identity];
}

RCT_EXPORT_METHOD(
                  logout
                  ) {
    [branchInstance logout];
}

RCT_EXPORT_METHOD(
                  userCompletedAction:(NSString *)event withState:(NSDictionary *)appState
                  ) {
    [branchInstance userCompletedAction:event withState:appState];
}

RCT_EXPORT_METHOD(
                  showShareSheet:(NSString *)identifier
                  withShareOptions:(NSDictionary *)shareOptionsMap
                  withLinkProperties:(NSDictionary *)linkPropertiesMap
                  withControlParams:(NSDictionary *)controlParamsMap
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    BranchUniversalObject *branchUniversalObject = [self findUniversalObjectWithIdent:identifier rejecter:reject];
    if (!branchUniversalObject) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *mutableControlParams = controlParamsMap.mutableCopy;
        if (shareOptionsMap && shareOptionsMap[@"emailSubject"]) {
            mutableControlParams[@"$email_subject"] = shareOptionsMap[@"emailSubject"];
        }

        BranchLinkProperties *linkProperties = [self createLinkProperties:linkPropertiesMap withControlParams:mutableControlParams];

        [branchUniversalObject showShareSheetWithLinkProperties:linkProperties
                                                   andShareText:shareOptionsMap[@"messageBody"]
                                             fromViewController:self.currentViewController
                                            completionWithError:^(NSString * _Nullable activityType, BOOL completed, NSError * _Nullable activityError){
                                                if (activityError) {
                                                    NSString *errorCodeString = [NSString stringWithFormat:@"%ld", (long)activityError.code];
                                                    reject(errorCodeString, activityError.localizedDescription, activityError);
                                                    return;
                                                }

                                                NSDictionary *result = @{
                                                                         @"channel" : activityType ?: [NSNull null],
                                                                         @"completed" : @(completed),
                                                                         @"error" : [NSNull null]
                                                                         };

                                                resolve(result);
                                            }];
    });
}

RCT_EXPORT_METHOD(
                  registerView:(NSString *)identifier
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    BranchUniversalObject *branchUniversalObject = [self findUniversalObjectWithIdent:identifier rejecter:reject];
    if (!branchUniversalObject) return;

    [branchUniversalObject registerViewWithCallback:^(NSDictionary *params, NSError *error) {
        if (!error) {
            resolve([NSNull null]);
        } else {
            reject([NSString stringWithFormat: @"%lu", (long)error.code], error.localizedDescription, error);
        }
    }];
}

RCT_EXPORT_METHOD(
                  generateShortUrl:(NSString *)identifier
                  withLinkProperties:(NSDictionary *)linkPropertiesMap
                  withControlParams:(NSDictionary *)controlParamsMap
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    BranchUniversalObject *branchUniversalObject = [self findUniversalObjectWithIdent:identifier rejecter:reject];
    if (!branchUniversalObject) return;

    BranchLinkProperties *linkProperties = [self createLinkProperties:linkPropertiesMap withControlParams:controlParamsMap];

    [branchUniversalObject getShortUrlWithLinkProperties:linkProperties andCallback:^(NSString *url, NSError *error) {
        if (!error) {
            RCTLogInfo(@"RNBranch Success");
            resolve(@{ @"url": url });
        } else {
            reject([NSString stringWithFormat: @"%lu", (long)error.code], error.localizedDescription, error);
        }
    }];
}

RCT_EXPORT_METHOD(
                  listOnSpotlight:(NSString *)identifier
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    BranchUniversalObject *branchUniversalObject = [self findUniversalObjectWithIdent:identifier rejecter:reject];
    if (!branchUniversalObject) return;

    [branchUniversalObject listOnSpotlightWithCallback:^(NSString *string, NSError *error) {
        if (!error) {
            NSDictionary *data = @{@"result":string};
            resolve(data);
        } else {
            reject([NSString stringWithFormat: @"%lu", (long)error.code], error.localizedDescription, error);
        }
    }];
}

// @TODO can this be removed? legacy, short url should be created from BranchUniversalObject
RCT_EXPORT_METHOD(
                  getShortUrl:(NSDictionary *)linkPropertiesMap
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    NSString *feature = linkPropertiesMap[@"feature"];
    NSString *channel = linkPropertiesMap[@"channel"];
    NSString *stage = linkPropertiesMap[@"stage"];
    NSArray *tags = linkPropertiesMap[@"tags"];

    [branchInstance getShortURLWithParams:linkPropertiesMap
                                  andTags:tags
                               andChannel:channel
                               andFeature:feature
                                 andStage:stage
                              andCallback:^(NSString *url, NSError *error) {
                                  if (error) {
                                      RCTLogError(@"RNBranch::Error: %@", error.localizedDescription);
                                      reject(@"RNBranch::Error", @"getShortURLWithParams", error);
                                  }
                                  resolve(url);
                              }];
}

RCT_EXPORT_METHOD(
                  loadRewards:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    [branchInstance loadRewardsWithCallback:^(BOOL changed, NSError *error) {
        if(!error) {
            int credits = (int)[branchInstance getCredits];
            resolve(@{@"credits": @(credits)});
        } else {
            RCTLogError(@"Load Rewards Error: %@", error.localizedDescription);
            reject(@"RNBranch::Error::loadRewardsWithCallback", @"loadRewardsWithCallback", error);
        }
    }];
}

RCT_EXPORT_METHOD(
                  redeemRewards:(NSInteger *)amount
                  inBucket:(NSString *)bucket
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    if (bucket) {
        [branchInstance redeemRewards:amount forBucket:bucket callback:^(BOOL changed, NSError *error) {
            if (!error) {
                resolve(@{@"changed": @(changed)});
            } else {
                RCTLogError(@"Redeem Rewards Error: %@", error.localizedDescription);
                reject(@"RNBranch::Error::redeemRewards", error.localizedDescription, error);
            }
        }];
    } else {
        [branchInstance redeemRewards:amount callback:^(BOOL changed, NSError *error) {
            if (!error) {
                resolve(@{@"changed": @(changed)});
            } else {
                RCTLogError(@"Redeem Rewards Error: %@", error.localizedDescription);
                reject(@"RNBranch::Error::redeemRewards", error.localizedDescription, error);
            }
        }];
    }
}

RCT_EXPORT_METHOD(
                  getCreditHistory:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject
                  ) {
    [branchInstance getCreditHistoryWithCallback:^(NSArray *list, NSError *error) {
        if (!error) {
            resolve(list);
        } else {
            RCTLogError(@"Credit History Error: %@", error.localizedDescription);
            reject(@"RNBranch::Error::getCreditHistory", error.localizedDescription, error);
        }
    }];
}

RCT_EXPORT_METHOD(
                  createUniversalObject:(NSDictionary *)universalObjectProperties
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(__unused RCTPromiseRejectBlock)reject
                  ) {
    BranchUniversalObject *universalObject = [[BranchUniversalObject alloc] initWithMap:universalObjectProperties];
    NSString *identifier = [NSUUID UUID].UUIDString;
    self.universalObjectMap[identifier] = universalObject;
    resolve(@{IdentFieldName: identifier});
}

RCT_EXPORT_METHOD(
                  releaseUniversalObject:(NSString *)identifier
                  ) {
    [self.universalObjectMap removeObjectForKey:identifier];
}

@end
