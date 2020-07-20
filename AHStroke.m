#import "AHStroke.h"

//#define SHOW_INPUT_POINTS       YES
//#define SHOW_STROKE_VERTICES    YES

#define CURVE_APPROXIMATION_THRESHOLD   0.001

typedef struct {
    AHVertex *vertices;
    GLsizei totalVertexCount;
    GLsizei overwritableVertexCount;
    CGRect  boundingRect;
} segmentInfo_t;

@interface AHStroke()
{
    GLsizei         _vertexCount, _overwritableVertexCount;
    GLsizei         _vertexBufferLength, _linecapBufferLength;
    NSMutableArray  *_inputPoints;
    
    GLsizei         _lastRenderedVertexCount;
    
    GLuint          _vao, _vbo;
    
    AHPathShader    *_shader;
    
    CGPoint         _bezierPoints[3];
    NSInteger       _bezierPointCounter;
    
    BOOL            _isFinished;
    
#ifdef SHOW_INPUT_POINTS
    AHVertex        *_inputVertices;
    GLsizei         _inputVertexCount;
    GLsizei         _inputVertexLength;
    GLuint          _inputVAO, _inputVBO;
#endif
}

@end

@implementation AHStroke

#pragma mark - Constructors

- (instancetype)init
{
    self = [super init];
    
    if (self)
    {
        _lineColor = [UIColor orangeColor];
        _lineOpacity = 1.0;
        _lineWidth = 10.0;
        
        _vertexCount = 0;
        _vertexBufferLength = 512;
        _vertices = malloc(_vertexBufferLength * sizeof(AHVertex));
        memset(_vertices, 0, _vertexBufferLength * sizeof(AHVertex));
        
        _linecapBufferLength = ((int)[self numLineCapSegments] + 2);

        _inputPoints = [NSMutableArray array];
        
        _lastRenderedVertexCount = 0;
        
#ifdef SHOW_INPUT_POINTS
        _inputVertexCount = 0;
        _inputVertexLength = 128;
        _inputVertices = malloc(_inputVertexLength * sizeof(AHVertex));
        memset(_inputVertices, 0, _inputVertexLength * sizeof(AHVertex));
#endif
        
        _isFinished = NO;
        
        [self prepareGLState];
    }
    
    return self;
}

- (instancetype)initWithShader:(AHPathShader *)shader
                         point:(CGPoint)point
                         color:(UIColor *)color
                     lineWidth:(float)lineWidth
{
    self = [self init];
    
    if (self)
    {
        _shader = shader;
        _lineWidth = lineWidth;
        _lineColor = color;
        const CGFloat *components = CGColorGetComponents(_lineColor.CGColor);
        _lineOpacity = components[3];
        
        _bezierPoints[0] = point;
        _bezierPointCounter = 1;
        
        [_inputPoints addObject:[NSValue valueWithCGPoint:point]];
        
        float xmin, xmax, ymin, ymax;
        
        xmin = floorf( point.x - self.lineWidth / 2.0 );
        xmax = ceilf( point.x + self.lineWidth / 2.0 );
        ymin = floorf( point.y - self.lineWidth / 2.0 );
        ymax = ceilf( point.y + self.lineWidth / 2.0 );
        
        _boundingRect = CGRectMake(xmin, ymin, xmax - xmin, ymax - ymin);
        
        AHVertex lineCapVertices[_linecapBufferLength];
        
        [self addFanLineCapToDestination:lineCapVertices
                         withStartNormal:GLKVector2Make(1.0, 0.0)
                           atCenterPoint:point];
        
        [self bufferVertices:lineCapVertices
                       count:_linecapBufferLength
           adjustVertexCount:YES];
        
        [self addFanLineCapToDestination:lineCapVertices
                         withStartNormal:GLKVector2Make(-1.0, 0.0)
                           atCenterPoint:point];
        
        [self bufferVertices:lineCapVertices
                       count:_linecapBufferLength
           adjustVertexCount:YES];
    }
    
    return self;
}

- (instancetype)initWithShader:(AHPathShader *)shader
                        points:(NSArray *)points
                         color:(UIColor *)color
                     lineWidth:(float)lineWidth
{
    self = [self init];
    
    if (self)
    {
        _shader = shader;
        _lineWidth = lineWidth;
        _lineColor = color;
        const CGFloat *components = CGColorGetComponents(_lineColor.CGColor);
        _lineOpacity = components[3];
        
        CGPoint firstPoint = [points.firstObject CGPointValue];
        _bezierPoints[0] = firstPoint;
        _bezierPointCounter = 1;
        
        [_inputPoints addObject:points.firstObject];
        
        float xmin, xmax, ymin, ymax;
        
        xmin = floorf( firstPoint.x - self.lineWidth / 2.0 );
        xmax = ceilf( firstPoint.x + self.lineWidth / 2.0 );
        ymin = floorf( firstPoint.y - self.lineWidth / 2.0 );
        ymax = ceilf( firstPoint.y + self.lineWidth / 2.0 );
        
        _boundingRect = CGRectMake(xmin, ymin, xmax - xmin, ymax - ymin);
        
        [self addLineCapsForPoints:points];
        
        _vertexCount = 2 * _linecapBufferLength;
        
        for (int i = 1; i < points.count; i++)
        {
            segmentInfo_t info = [self handlePoint:[points[i] CGPointValue]];
            
            GLsizei thisVertexCount = (i == points.count - 1) ? info.totalVertexCount : info.totalVertexCount - info.overwritableVertexCount;
            GLsizei newCount = _vertexCount + thisVertexCount;
            
            if (newCount >= _vertexBufferLength)
            {
                GLsizei newLength = _vertexBufferLength * 2;
                
                _vertices = realloc(_vertices, newLength * sizeof(AHVertex));
                _vertexBufferLength = newLength;
            }
            
            memcpy(_vertices + _vertexCount, info.vertices, thisVertexCount * sizeof(AHVertex));
            _vertexCount = newCount;
            
            free(info.vertices);
        }
        
        glBindVertexArrayOES(_vao);
        glBindBuffer(GL_ARRAY_BUFFER, _vbo);
        
        glBufferData(GL_ARRAY_BUFFER, _vertexCount * sizeof(AHVertex), _vertices, GL_STATIC_DRAW);
        
        glBindVertexArrayOES(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
    
    return self;
}

- (void)addLineCapsForPoints:(NSArray *)points
{
    if (points.count > 1)
    {
        CGPoint pts[4] = {
            [points[0] CGPointValue],
            [points[1] CGPointValue],
            [points[points.count - 2] CGPointValue],
            [points.lastObject CGPointValue]
        };
        
        CGPoint midPoint1 = CGPointMidPoint(pts[0], pts[1]);
        
        GLKVector2 normal1 = GLKVector2UnitNormal(pts[0], midPoint1);
        
        [self addFanLineCapToDestination:_vertices
                         withStartNormal:normal1
                           atCenterPoint:pts[0]];
        
        CGPoint midPoint2 = CGPointMidPoint(pts[2], pts[3]);
        GLKVector2 normal2 = GLKVector2UnitNormal(pts[3], midPoint2);
        
        [self addFanLineCapToDestination:(_vertices + _linecapBufferLength)
                         withStartNormal:normal2
                           atCenterPoint:pts[3]];
    }
    else
    {
        CGPoint firstPoint = [points.firstObject CGPointValue];
        
        [self addFanLineCapToDestination:_vertices
                         withStartNormal:GLKVector2Make(1.0, 0.0)
                           atCenterPoint:firstPoint];
        
        [self addFanLineCapToDestination:_vertices + _linecapBufferLength
                         withStartNormal:GLKVector2Make(-1.0, 0.0)
                           atCenterPoint:firstPoint];
    }
}

- (void)prepareGLState
{
    glGenVertexArraysOES(1, &_vao);
    glBindVertexArrayOES(_vao);
    
    glGenBuffers(1, &_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    glBufferData(GL_ARRAY_BUFFER, _vertexBufferLength * sizeof(AHVertex), _vertices, GL_DYNAMIC_DRAW);
    
    glVertexAttribPointer(AHVertexAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(AHVertex), (const GLvoid *) offsetof(AHVertex, Position));
    glEnableVertexAttribArray(AHVertexAttribPosition);
    
#ifdef SHOW_INPUT_POINTS
    glGenVertexArraysOES(1, &_inputVAO);
    glBindVertexArrayOES(_inputVAO);
    
    glGenBuffers(1, &_inputVBO);
    glBindBuffer(GL_ARRAY_BUFFER, _inputVBO);
    glBufferData(GL_ARRAY_BUFFER, _inputVertexLength * sizeof(AHVertex), _inputVertices, GL_DYNAMIC_DRAW);
    
    glEnableVertexAttribArray(AHVertexAttribPosition);
    glVertexAttribPointer(AHVertexAttribPosition, 2, GL_FLOAT, GL_FALSE, sizeof(AHVertex), (const GLvoid *) offsetof(AHVertex, Position));
#endif
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

#pragma mark - Overridden Properties

- (segmentInfo_t)handlePoint:(CGPoint)point
{
    if (_bezierPointCounter > 0 && CGPointEqualToPoint(point, _bezierPoints[_bezierPointCounter - 1]))
    {
        segmentInfo_t info;
        info.vertices = 0;
        info.totalVertexCount = 0;
        info.overwritableVertexCount = 0;
        info.boundingRect = CGRectZero;
        return info;
    }
    
    _bezierPoints[_bezierPointCounter] = point;
    _bezierPointCounter++;
    
    [_inputPoints addObject:[NSValue valueWithCGPoint:point]];
    
    CGPoint midPoint = CGPointMidPoint(_bezierPoints[0], _bezierPoints[1]);
    
    segmentInfo_t primarySegment;
    segmentInfo_t trailingSegment;
    
    // We're just starting the line.
    if (_bezierPointCounter < 3)
    {
        primarySegment = [self addLineSegmentFromPoint:_bezierPoints[0]
                                               toPoint:midPoint
                                   isLineOverwriteable:NO];
        
        trailingSegment = [self addLineSegmentFromPoint:midPoint
                                                toPoint:_bezierPoints[1]
                                    isLineOverwriteable:YES];
    }
    else
    {
        CGPoint midPoint2 = CGPointMidPoint(_bezierPoints[1], _bezierPoints[2]);
        
        primarySegment = [self addQuadraticBezierPointsFromPoint:midPoint
                                                         toPoint:midPoint2
                                                withControlPoint:_bezierPoints[1]];
        
        trailingSegment = [self addLineSegmentFromPoint:midPoint2
                                                toPoint:_bezierPoints[2]
                                    isLineOverwriteable:YES];
        
        _bezierPoints[0] = _bezierPoints[1];
        _bezierPoints[1] = _bezierPoints[2];
        _bezierPointCounter = 2;
    }
    
#ifdef SHOW_INPUT_POINTS
    if (_inputVertexCount < _inputVertexLength)
    {
        _inputVertices[_inputVertexCount] = (AHVertex){point.x, point.y};
        
        glBindVertexArrayOES(_inputVAO);
        glBindBuffer(GL_ARRAY_BUFFER, _inputVBO);
        _inputVertexCount++;
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }
#endif
    
    GLsizei vertexCount = primarySegment.totalVertexCount + trailingSegment.totalVertexCount;
    AHVertex *vertices = malloc(vertexCount * sizeof(AHVertex));
    memcpy(vertices, primarySegment.vertices, primarySegment.totalVertexCount * sizeof(AHVertex));
    memcpy(vertices + primarySegment.totalVertexCount, trailingSegment.vertices, trailingSegment.totalVertexCount * sizeof(AHVertex));
    free(primarySegment.vertices);
    free(trailingSegment.vertices);
    
    CGRect boundingRect = CGRectUnion(primarySegment.boundingRect, trailingSegment.boundingRect);
    
    segmentInfo_t info;
    info.vertices = vertices;
    info.totalVertexCount = vertexCount;
    info.overwritableVertexCount = trailingSegment.totalVertexCount;
    info.boundingRect = CGRectInset(boundingRect, -ceilf(self.lineWidth / 2.0), -ceilf(self.lineWidth / 2.0));
    
    _boundingRect = CGRectUnion(_boundingRect, info.boundingRect);
    
    return info;
}

- (void)updateEndcapsBuffer
{
    CGPoint midPoint = CGPointMidPoint(_bezierPoints[0], _bezierPoints[1]);
    
    glBindVertexArrayOES(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    // We're just starting the line.
    if (_inputPoints.count < 3)
    {
        GLKVector2 normal = GLKVector2UnitNormal(midPoint, _bezierPoints[1]);
        GLKVector2 antiNormal = GLKVector2Make(-normal.x, -normal.y);
        
        [self addFanLineCapToDestination:_vertices
                         withStartNormal:normal
                           atCenterPoint:_bezierPoints[0]];
        
        [self addFanLineCapToDestination:_vertices + _linecapBufferLength
                         withStartNormal:antiNormal
                           atCenterPoint:_bezierPoints[1]];
        
        glBufferSubData(GL_ARRAY_BUFFER, 0, _linecapBufferLength * sizeof(AHVertex), _vertices);
    }
    else
    {
        // KEEP IN MIND THAT AT THIS POINT, THE BEZIER POINTS HAVE BEEN SHIFTED BACK AN INDEX!!
        CGPoint midPoint2 = CGPointMidPoint(_bezierPoints[0], _bezierPoints[1]);
        GLKVector2 normal = GLKVector2UnitNormal(_bezierPoints[1], midPoint2);
        
        [self addFanLineCapToDestination:(_vertices + _linecapBufferLength)
                         withStartNormal:normal
                           atCenterPoint:_bezierPoints[1]];
        
        glBufferSubData(GL_ARRAY_BUFFER, _linecapBufferLength * sizeof(AHVertex), _linecapBufferLength * sizeof(AHVertex), _vertices + _linecapBufferLength);
    }
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArrayOES(0);
}

#pragma mark - Vertex Generation

- (void)addFanLineCapToDestination:(AHVertex *)destination
                   withStartNormal:(GLKVector2)startNormal
                     atCenterPoint:(CGPoint)point;
{
    GLKVector2 cp = GLKVector2Make(point.x, point.y);
    AHVertex cpVertex = AHVertexMakeWithGLKVector2(cp);
    GLKVector2 scaledVector = GLKVector2MultiplyScalar(startNormal, self.lineWidth / 2.0);
    
    for (int i = 0; i < _linecapBufferLength; i++)
    {
        if (i == 0)
        {
            destination[i] = cpVertex;
        }
        else
        {
            float thisAngle = M_PI * (float) (i - 1.0) / (_linecapBufferLength - 2.0);
            
            GLKMatrix3 rotationMatrix = GLKMatrix3MakeRotation(thisAngle, 0, 0, 1.0);
            GLKVector3 rotatedVector3D = GLKMatrix3MultiplyVector3(rotationMatrix, GLKVector3Make(scaledVector.x, scaledVector.y, 0));
            GLKVector2 centeredVector = GLKVector2Add(cp, GLKVector2Make(rotatedVector3D.x, rotatedVector3D.y));
            
            destination[i] = AHVertexMakeWithGLKVector2(centeredVector);
        }
    }
}

- (CGRect)addTriangleStripLineCapWithStartNormal:(GLKVector2)startNormal
                                 withOffsetAngle:(float)offsetAngle
                                   atCenterPoint:(CGPoint)point;
{
    GLKVector2 cp = GLKVector2Make(point.x, point.y);
    GLKVector2 scaledVector = GLKVector2MultiplyScalar(startNormal, self.lineWidth / 2.0);
    
    NSInteger numIterations = [self numLineCapSegments] + 1;
    NSInteger numVertices = 2 * numIterations;
    
    AHVertex *vertices = malloc(numVertices * sizeof(AHVertex));
    
    CGFloat maxX, minX, maxY, minY;
    maxX = minX = point.x;
    maxY = minY = point.y;
    
    for (int i = 0; i < numIterations; i++)
    {
        float thisAngle = offsetAngle + M_PI * i / (numIterations - 1);
        
        GLKMatrix3 rotationMatrix = GLKMatrix3MakeRotation(thisAngle, 0, 0, 1.0);
        GLKVector3 rotatedVector3D = GLKMatrix3MultiplyVector3(rotationMatrix, GLKVector3Make(scaledVector.x, scaledVector.y, 0));
        GLKVector2 centeredVector = GLKVector2Add(cp, GLKVector2Make(rotatedVector3D.x, rotatedVector3D.y));
        GLKVector2 antiVector = GLKVector2Subtract(centeredVector, GLKVector2Make(rotatedVector3D.x, rotatedVector3D.y));
        
        vertices[2 * i] = AHVertexMakeWithGLKVector2(centeredVector);
        vertices[2 * i + 1] = AHVertexMakeWithGLKVector2(antiVector);
        
        maxX = MAX(maxX, MAX(centeredVector.x, antiVector.x));
        minX = MIN(minX, MIN(centeredVector.x, antiVector.x));
        maxY = MAX(maxY, MAX(centeredVector.y, antiVector.y));
        minY = MIN(minY, MIN(centeredVector.y, antiVector.y));
    }
    
    [self bufferVertices:vertices
                   count:(GLsizei)numVertices
       adjustVertexCount:YES];
    
    free(vertices);
    
    return CGRectMake(minX, minY, maxX - minX, maxY - minY);
}

- (NSInteger)numLineCapSegments
{
    float arclength = M_PI * self.lineWidth / 2.0;
    
    return (NSInteger) MAX(3, arclength / 1.0f);
}

- (segmentInfo_t)addLineSegmentFromPoint:(CGPoint)fromPt
                                 toPoint:(CGPoint)toPt
                     isLineOverwriteable:(BOOL)isOverwriteable
{
    GLKVector2 normal = GLKVector2UnitNormal(fromPt, toPt);
    GLKVector2 pt0 = GLKVector2Make(fromPt.x, fromPt.y);
    GLKVector2 pt1 = GLKVector2Make(toPt.x, toPt.y);
    
    GLKVector2 halfWidthVector = GLKVector2MultiplyScalar(normal, self.lineWidth / 2.0);
    
    GLKVector2 quadPoint0 = GLKVector2Add(pt0, halfWidthVector);
    GLKVector2 quadPoint1 = GLKVector2Subtract(pt0, halfWidthVector);
    GLKVector2 quadPoint2 = GLKVector2Add(pt1, halfWidthVector);
    GLKVector2 quadPoint3 = GLKVector2Subtract(pt1, halfWidthVector);
    
    AHVertex *vertices = malloc(4 * sizeof(AHVertex));
    
    vertices[0] = AHVertexMakeWithGLKVector2(quadPoint0);
    vertices[1] = AHVertexMakeWithGLKVector2(quadPoint1);
    vertices[2] = AHVertexMakeWithGLKVector2(quadPoint2);
    vertices[3] = AHVertexMakeWithGLKVector2(quadPoint3);
    
    
    float xmin, xmax, ymin, ymax;
    xmin = xmax = quadPoint0.x;
    ymin = ymax = quadPoint0.y;
    
    for (int i = 1; i < 4; i++)
    {
        xmin = MIN(xmin, vertices[i].Position[0]);
        xmax = MAX(xmax, vertices[i].Position[0]);
        ymin = MIN(ymin, vertices[i].Position[1]);
        ymax = MAX(ymax, vertices[i].Position[1]);
    }
    
    CGRect boundingRect = CGRectMake(xmin, ymin, xmax - xmin, ymax - ymin);
    
    segmentInfo_t segmentInfo;
    segmentInfo.vertices = vertices;
    segmentInfo.totalVertexCount = 4;
    segmentInfo.overwritableVertexCount = isOverwriteable ? 4 : 0;
    segmentInfo.boundingRect = boundingRect;
    
    return segmentInfo;
}

- (segmentInfo_t)addQuadraticBezierPointsFromPoint:(CGPoint)fromPt
                                           toPoint:(CGPoint)toPt
                                  withControlPoint:(CGPoint)controlPoint
{
    GLKVector2 ray1 = GLKVector2Make(controlPoint.x - fromPt.x, controlPoint.y - fromPt.y);
    GLKVector2 ray2 = GLKVector2Make(toPt.x - controlPoint.x, toPt.y - controlPoint.y);
    
    if (GLKVector2IsParallel(ray1, ray2) || CGPointEqualToPoint(fromPt, toPt))
    {
        CGFloat inflectionXT = (fromPt.x - controlPoint.x) / (toPt.x - 2 * controlPoint.x + fromPt.x);
        CGFloat inflectionYT = (fromPt.y - controlPoint.y) / (toPt.y - 2 * controlPoint.y + fromPt.y);
        
        if ((inflectionXT < 1.0 && inflectionXT > 0.0) ||
            (inflectionYT < 1.0 && inflectionYT > 0.0))
        {
            inflectionXT = isnan(inflectionXT) ? 0 : inflectionXT;
            inflectionYT = isnan(inflectionYT) ? 0 : inflectionYT;
            
            CGFloat maxT = ((inflectionXT + inflectionYT) / 2.0);
            
            // Equation of Bezier Curve.
            CGFloat x = (1 - maxT) * (1 - maxT) * fromPt.x + 2 * (1 - maxT) * maxT * controlPoint.x + maxT * maxT * toPt.x;
            CGFloat y = (1 - maxT) * (1 - maxT) * fromPt.y + 2 * (1 - maxT) * maxT * controlPoint.y + maxT * maxT * toPt.y;
            
            CGPoint maxPoint = CGPointMake(isnan(x) ? fromPt.x : x, isnan(y) ? fromPt.y : y);
            segmentInfo_t segment1 = [self addLineSegmentFromPoint:fromPt
                                                           toPoint:maxPoint
                                               isLineOverwriteable:NO];
            
            CGRect capRect = [self addTriangleStripLineCapWithStartNormal:GLKVector2Normalize(ray1)
                                                          withOffsetAngle:-M_PI_2
                                                            atCenterPoint:maxPoint];
            
            segmentInfo_t segment2 = [self addLineSegmentFromPoint:maxPoint
                                                           toPoint:toPt
                                               isLineOverwriteable:NO];
            
            GLsizei count = segment1.totalVertexCount + segment2.totalVertexCount;
            AHVertex *vertices = malloc(count * sizeof(AHVertex));
            memcpy(vertices, segment1.vertices, segment1.totalVertexCount * sizeof(AHVertex));
            memcpy(vertices + segment1.totalVertexCount, segment2.vertices, segment2.totalVertexCount * sizeof(AHVertex));
            free(segment1.vertices);
            free(segment2.vertices);
            
            segmentInfo_t retInfo;
            retInfo.vertices = vertices;
            retInfo.totalVertexCount = count;
            retInfo.overwritableVertexCount = 0;
            retInfo.boundingRect = CGRectUnion(segment1.boundingRect, capRect);
            
            return retInfo;
        }
        else
        {
            return [self addLineSegmentFromPoint:fromPt
                                         toPoint:toPt
                             isLineOverwriteable:NO];
        }
    }
    
    float estimatedLength = (GLKVector2Length(ray1) +
                             GLKVector2Length(ray2));
    
    NSInteger numSubDivisions = MAX(estimatedLength / 4.0f, 1);
    NSInteger bufferLength = 4 * 2 * (numSubDivisions + 1);
    GLsizei currentVertexCount = 0;
    
    AHVertex *bezierVertices = malloc(bufferLength * sizeof(AHVertex));
    
    GLKVector3 lastTangent;
    GLKVector2 lastPoint;
    CGRect boundingRect;
    
    float lastT = 0;
    
    for (int i = 0; i < numSubDivisions + 1; i++)
    {
        float t = i / (numSubDivisions);
        
        [self addBezierVerticesFromPt:fromPt
                              toPoint:toPt
                         controlPoint:controlPoint
                                    t:t
                                lastT:lastT
                       toVertexBuffer:&bezierVertices
                             ofLength:&bufferLength
                    withExistingCount:&currentVertexCount
                          lastTangent:&lastTangent
                            lastPoint:&lastPoint
                         boundingRect:&boundingRect];
        
        lastT = t;
    }
    
    segmentInfo_t retInfo;
    retInfo.vertices = bezierVertices;
    retInfo.totalVertexCount = currentVertexCount;
    retInfo.overwritableVertexCount = 0;
    retInfo.boundingRect = boundingRect;
    
    return retInfo;
}

- (void)addBezierVerticesFromPt:(CGPoint)fromPt
                        toPoint:(CGPoint)toPt
                   controlPoint:(CGPoint)controlPt
                              t:(float)t
                          lastT:(float)lastT
                 toVertexBuffer:(AHVertex **)vertices
                       ofLength:(NSInteger *)length
              withExistingCount:(GLsizei *)count
                    lastTangent:(GLKVector3 *)lastTangent
                      lastPoint:(GLKVector2 *)lastPoint
                   boundingRect:(CGRect*)rect
{
    // Equation of Bezier Curve.
    float x = (1 - t) * (1 - t) * fromPt.x + 2 * (1 - t) * t * controlPt.x + t * t * toPt.x;
    float y = (1 - t) * (1 - t) * fromPt.y + 2 * (1 - t) * t * controlPt.y + t * t * toPt.y;
    
    GLKVector2 thisPoint = GLKVector2Make(x, y);
    
    // Equation of Bezier Curve first derivative.  The output is a tangent vector.
    float tanX = 2 * (1 - t) * (controlPt.x - fromPt.x) + 2 * t * (toPt.x - controlPt.x);
    float tanY = 2 * (1 - t) * (controlPt.y - fromPt.y) + 2 * t * (toPt.y - controlPt.y);
    
    GLKVector2 tangent2D = GLKVector2Normalize(GLKVector2Make(tanX, tanY));
    GLKVector3 tangent = GLKVector3Make(tangent2D.x, tangent2D.y, 0);
    
    float error = 0;
    
    if (t > 0)
    {
        float angleBetweenTangents = acosf(GLKVector3DotProduct(tangent, *lastTangent));
        float distance = GLKVector2Distance(*lastPoint, thisPoint);
        float thisRadius = distance / 2.0 / sinf(angleBetweenTangents / 2.0);
        float thisArcLength = thisRadius * angleBetweenTangents;
        error = ABS((thisArcLength - distance) / thisArcLength);
    }
    
    if (error > CURVE_APPROXIMATION_THRESHOLD)
    {
        [self addBezierVerticesFromPt:fromPt
                              toPoint:toPt
                         controlPoint:controlPt
                                    t:(t + lastT) / 2.0
                                lastT:lastT
                       toVertexBuffer:vertices
                             ofLength:length
                    withExistingCount:count
                          lastTangent:lastTangent
                            lastPoint:lastPoint
                         boundingRect:rect];
        
        [self addBezierVerticesFromPt:fromPt
                              toPoint:toPt
                         controlPoint:controlPt
                                    t:t
                                lastT:(t + lastT) / 2.0
                       toVertexBuffer:vertices
                             ofLength:length
                    withExistingCount:count
                          lastTangent:lastTangent
                            lastPoint:lastPoint
                         boundingRect:rect];
    }
    else
    {
        if (*count + 2 > *length)
        {
            *length *= 2;
            *vertices = realloc(*vertices, *length * sizeof(AHVertex));
        }
        
        GLKVector3 normal3D = GLKMatrix3MultiplyVector3(GLKMatrix3MakeRotation(M_PI_2, 0, 0, 1.0), tangent);
        GLKVector2 normal = GLKVector2Normalize(GLKVector2Make(normal3D.x, normal3D.y));
        GLKVector2 halfWidthNormal = GLKVector2MultiplyScalar(normal, self.lineWidth / 2.0);
        
        GLKVector2 pt0 = GLKVector2Add(thisPoint, halfWidthNormal);
        GLKVector2 pt1 = GLKVector2Subtract(thisPoint, halfWidthNormal);
        
        *(*vertices + *count) = AHVertexMakeWithGLKVector2(pt0);
        *(*vertices + *count + 1) = AHVertexMakeWithGLKVector2(pt1);
        *count += 2;
        
        *lastTangent = tangent;
        *lastPoint = thisPoint;
        
        CGRect thisRect = CGRectMake(MIN(pt0.x, pt1.x), MIN(pt0.y, pt1.y), ABS(pt1.x - pt0.x), ABS(pt1.y - pt0.y));
        
        *rect = (t == 0) ? thisRect : CGRectUnion(thisRect, *rect);
    }
}

- (void)bufferVertices:(AHVertex *)vertices
                 count:(GLsizei)count
     adjustVertexCount:(BOOL)adjustVertexCount
{
    GLsizei newCount = _vertexCount + count;
    
    glBindVertexArrayOES(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    if (newCount >= _vertexBufferLength)
    {
        GLsizei newLength = _vertexBufferLength * 2;
        
        AHVertex *newBuffer = malloc(newLength * sizeof(AHVertex));
        memcpy(newBuffer, _vertices, _vertexBufferLength * sizeof(AHVertex));
        free(_vertices);
        _vertices = newBuffer;
        
        memcpy(_vertices + _vertexCount, vertices, count * sizeof(AHVertex));
        
        _vertexBufferLength = newLength;
        glBufferData(GL_ARRAY_BUFFER, _vertexBufferLength * sizeof(AHVertex), _vertices, GL_DYNAMIC_DRAW);
    }
    else
    {
        memcpy(_vertices + _vertexCount, vertices, count * sizeof(AHVertex));
        glBufferSubData(GL_ARRAY_BUFFER, _vertexCount * sizeof(AHVertex), count * sizeof(AHVertex), vertices);
    }
    
    if (adjustVertexCount)
    {
        _vertexCount += count;
        _overwritableVertexCount = 0;
    }
    else
    {
        _overwritableVertexCount = count;
    }
    
    glBindVertexArrayOES(0);
    glBindBuffer(GL_ARRAY_BUFFER, 0);
}

#pragma mark - Public API

- (CGRect)appendCGPoint:(CGPoint)point
{
    segmentInfo_t info = [self handlePoint:point];
    
    [self updateEndcapsBuffer];
    
    GLsizei offset = info.totalVertexCount - info.overwritableVertexCount;
    
    if (offset > 0)
    {
        [self bufferVertices:info.vertices
                       count:offset
           adjustVertexCount:YES];
        
        if (info.overwritableVertexCount > 0)
        {
            [self bufferVertices:info.vertices + offset
                           count:info.overwritableVertexCount
               adjustVertexCount:NO];
        }
    }
    
    free(info.vertices);
    
    return info.boundingRect;
}

- (CGRect)finishWithCGPoint:(CGPoint)point
{
    NSAssert(!_isFinished, @"");
    
    _isFinished = YES;
    
    CGRect retRect;
    
    if (self.inputPoints.count == 1 && CGPointEqualToPoint(point, [self.inputPoints[0] CGPointValue]))
    {
        retRect = self.boundingRect;
    }
    else
    {
        retRect = [self appendCGPoint:point];
    }
    
    _vertexCount += _overwritableVertexCount;
    _overwritableVertexCount = 0;
    
    glBindVertexArrayOES(_vao);
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    
    glBufferData(GL_ARRAY_BUFFER, _vertexCount * sizeof(AHVertex), _vertices, GL_STATIC_DRAW);
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArrayOES(0);
    
    return retRect;
}

#pragma mark - Draw

- (void)render
{
    const CGFloat *colorComponents = CGColorGetComponents(self.lineColor.CGColor);
    _shader.color = GLKVector4Make(colorComponents[0],
                                   colorComponents[1],
                                   colorComponents[2],
                                   1.0);
    
    [_shader prepareToDraw];
    
    glBindVertexArrayOES(_vao);
    
    glBindBuffer(GL_ARRAY_BUFFER, _vbo);
    glDrawArrays(GL_TRIANGLE_FAN, 0, _linecapBufferLength);
    glDrawArrays(GL_TRIANGLE_FAN, _linecapBufferLength, _linecapBufferLength);
    glDrawArrays(GL_TRIANGLE_STRIP, 2 * _linecapBufferLength, _vertexCount + _overwritableVertexCount - 2 * _linecapBufferLength);
    
#ifdef SHOW_STROKE_VERTICES
    _shader.color = GLKVector4Make(0.0, 1.0, 1.0, 1.0);
    [_shader prepareToDraw];
    
    glDrawArrays(GL_LINE_STRIP, 2 * _linecapBufferLength, _vertexCount + _overwritableVertexCount - 2 * _linecapBufferLength);
#endif
    
#ifdef SHOW_INPUT_POINTS
    _shader.color = GLKVector4Make(0.0, 0.0, 0.0, 1.0);
    [_shader prepareToDraw];
    
    glBindVertexArrayOES(_inputVAO);
    glBindBuffer(GL_ARRAY_BUFFER, _inputVBO);
    glBufferData(GL_ARRAY_BUFFER, _inputVertexCount * sizeof(AHVertex), _inputVertices, GL_DYNAMIC_DRAW);
    glDrawArrays(GL_POINTS, 0, _inputVertexCount);
#endif
    
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glBindVertexArrayOES(0);
}

#pragma mark - Dealloc

- (void)dealloc
{
    if (_vertexCount > 0)
    {
        free(_vertices);
    }
    
    if (_vao != 0)
    {
        glDeleteVertexArraysOES(1, &_vao);
    }
    
    if (_vbo != 0)
    {
        glDeleteBuffers(1, &_vbo);
    }
    
#ifdef SHOW_INPUT_POINTS
    if (_inputVertexCount > 0)
    {
        free(_inputVertices);
    }
#endif
}

@end
