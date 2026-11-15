#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol AyuPythonNativeDelegate <NSObject>
- (void)pythonLogWithLevel:(NSString *)level pluginId:(NSString *)pluginId message:(NSString *)message;
- (NSString *)pythonGetSettingForPlugin:(NSString *)pluginId key:(NSString *)key defaultJSON:(NSString *)defaultJSON;
- (void)pythonSetSettingForPlugin:(NSString *)pluginId key:(NSString *)key valueJSON:(NSString *)valueJSON;
- (void)pythonShowBulletinWithTitle:(NSString *)title subtitle:(NSString *)subtitle icon:(NSString *)icon;
- (void)pythonShowAlertWithTitle:(NSString *)title message:(NSString *)message buttonsJSON:(NSString *)buttonsJSON;
- (NSString *)pythonSendMessageWithParamsJSON:(NSString *)paramsJSON;
- (NSString *)pythonExecuteRequestWithMethod:(NSString *)method paramsJSON:(NSString *)paramsJSON;
- (NSString *)pythonGetCurrentAccountJSON;
@end

@interface AyuPythonRuntime : NSObject

+ (instancetype)sharedRuntime;

@property (nonatomic, weak, nullable) id<AyuPythonNativeDelegate> delegate;
@property (nonatomic, readonly, getter=isInitialized) BOOL initialized;

- (BOOL)initializeWithBundlePath:(NSString *)bundlePath
                 extraSearchPath:(nullable NSString *)extraSearchPath
                           error:(NSError * _Nullable * _Nullable)error;

- (NSString *)dispatchCommand:(NSString *)command payloadJSON:(NSString *)payloadJSON;

- (void)shutdown;

@end

NS_ASSUME_NONNULL_END
