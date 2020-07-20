uniform highp mat4 u_ProjectionMatrix;

attribute vec4 a_Position;
attribute vec2 a_TexCoord;

varying lowp vec2 frag_TexCoord;

void main(void)
{
    gl_Position = u_ProjectionMatrix * a_Position;
    frag_TexCoord = a_TexCoord;
}