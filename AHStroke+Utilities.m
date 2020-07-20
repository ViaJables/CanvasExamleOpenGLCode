#import "AHStroke+Utilities.h"
#import "AHPersistentStroke.h"
#import "UIColor+Expanded.h"

@implementation AHStroke (Utilities)

+ (instancetype)strokeFromPersistentStroke:(AHPersistentStroke *)persistentStroke
                                withShader:(AHPathShader *)shader
{
    AHStroke *stroke = [[AHStroke alloc] initWithShader:shader
                                                 points:(NSArray *)persistentStroke.inputPoints
                                                  color:[UIColor colorWithRed:persistentStroke.r.floatValue
                                                                        green:persistentStroke.g.floatValue
                                                                         blue:persistentStroke.b.floatValue
                                                                        alpha:persistentStroke.a.floatValue]
                                              lineWidth:persistentStroke.lineWidth.floatValue];
    
    return stroke;
}

- (NSString *)svgString
{
    NSMutableString *pathString = [[NSMutableString alloc] init];
    
    if (self.inputPoints.count == 1)
    {
        CGPoint thisPoint = [self.inputPoints.firstObject CGPointValue];
        [pathString appendFormat:@"M %0.4f %0.4f L %0.4f %0.4f ", thisPoint.x, thisPoint.y, thisPoint.x, thisPoint.y];
    }
    else if (self.inputPoints.count == 2)
    {
        CGPoint initialPoint = [self.inputPoints.firstObject CGPointValue];
        CGPoint finalPoint = [self.inputPoints.lastObject CGPointValue];
        [pathString appendFormat:@"M %0.4f %0.4f L %0.4f %0.4f ", initialPoint.x, initialPoint.y, finalPoint.x, finalPoint.y];
    }
    else
    {
        for (int i = 1; i < self.inputPoints.count; i++)
        {
            CGPoint lastPoint = [self.inputPoints[i - 1] CGPointValue];
            CGPoint thisPoint = [self.inputPoints[i] CGPointValue];
            CGPoint thisMidPoint = CGPointMidPoint(thisPoint, lastPoint);
            
            if (i == 1)
            {
                [pathString appendFormat:@"M %0.4f %0.4f L %0.4f %0.4f ", lastPoint.x, lastPoint.y, thisMidPoint.x, thisMidPoint.y];
            }
            else
            {
                [pathString appendFormat:@"Q %0.4f %0.4f %0.4f %0.4f ", lastPoint.x, lastPoint.y, thisMidPoint.x, thisMidPoint.y];
            }
            
            if (i == self.inputPoints.count - 1)
            {
                [pathString appendFormat:@"L %0.4f %0.4f", thisPoint.x, thisPoint.y];
            }
        }
    }
    
    return [NSString stringWithFormat:@"<path d=\"%@\" stroke=\"#%@\" stroke-opacity=\"%0.4f\" stroke-width=\"%0.4f\" stroke-linecap=\"round\" stroke-linejoin=\"round\" fill-opacity=\"0\" />",
            [pathString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
            [self.lineColor hexStringFromColor],
            self.lineOpacity,
            self.lineWidth];
}

@end
