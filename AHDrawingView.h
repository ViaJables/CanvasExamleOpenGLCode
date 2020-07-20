#import <GLKit/GLKit.h>

@class AHDrawingView, AHPersistentDrawing, AHStroke;

/**
 Delegate to communicate between a drawing view and its controller.
 */
@protocol AHDrawingViewDelegate <NSObject>

@optional
/**
 Notifies the delegate that the drawing view will draw (a stroke is about to begin).
 
 @param drawingView The drawing view about to get drawn on.
 */
- (void)drawingViewWillDraw:(AHDrawingView *)drawingView;

/**
 Notifies the delegate that the drawing view was drawn on (a stroke ended).
 
 @param drawingView The drawing view that got drawn on.
 */
- (void)drawingView:(AHDrawingView *)drawingView
      didDrawStroke:(AHStroke *)stroke;

@end

@interface AHDrawingView : UIView

/**
 Sets the width of the line that gets drawn.
 */
@property (nonatomic, assign) CGFloat lineWidth;

/**
 Sets the color of the line that gets drawn.
 */
@property (nonatomic, strong) UIColor *lineColor;

/**
 Sets the opacity of the line that gets drawn.
 */
@property (nonatomic, assign) CGFloat lineOpacity;

/**
 The delegate to communicate with for updates in the view.
 */
@property (weak, nonatomic) IBOutlet id<AHDrawingViewDelegate> drawingDelegate;

- (BOOL)canUndo;

- (void)undo;
- (void)clear;

- (UIImage *)imageWithScale:(CGFloat)scale;
- (UIImage *)imageWithScale:(CGFloat)scale backgroundColor:(UIColor *)backgroundColor;

- (void)loadPersistentDrawing:(AHPersistentDrawing *)persistentDrawing
                 onCompletion:(void(^)(void))completion;

@end
