uniform lowp vec4 u_Color;
uniform sampler2D u_Texture;

void main(void)
{
//    gl_FragColor = u_Color * texture2D(u_Texture, gl_PointCoord);
    gl_FragColor = u_Color;
}