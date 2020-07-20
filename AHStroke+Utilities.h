
#import "AHStroke.h"

@class AHPersistentStroke;

@interface AHStroke (Utilities)

+ (instancetype)strokeFromPersistentStroke:(AHPersistentStroke *)persistentStroke
                                withShader:(AHPathShader *)shader;

- (NSString *)svgString;

@end
