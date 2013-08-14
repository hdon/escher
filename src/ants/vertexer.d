module ants.vertexer;
import ants.shader;
import gl3n.linalg : Vector, Matrix;
import derelict.opengl3.gl3;
import ants.texture;
import ants.material;

private alias Vector!(double, 3) vec3d;
private alias Vector!(double, 2) vec2d;
private alias Vector!(float, 3) vec3f;
alias Matrix!(double, 4, 4) mat4d;
alias Matrix!(float, 4, 4) mat4f;

class Vertexer
{
  double[]  positions;
  double[]  UVs;
  float[]   colors;
  uint      numVerts;

  this()
  {
  }

  void add(vec3d pos, vec2d uv, vec3f color)
  {
    positions ~= pos.x;
    positions ~= pos.y;
    positions ~= pos.z;
    colors ~= color.x;
    colors ~= color.y;
    colors ~= color.z;
    UVs ~= uv.x;
    UVs ~= uv.y;
    numVerts++;
  }

  void draw(ShaderProgram shaderProgram, mat4d mvMatd, mat4d pMatd, Material material)
  {
    Texture myTex;
    if (material !is null)
      myTex = material.texes[0].texture; // XXX

    // XXX
    mat4f mvMat = mat4f(mvMatd);
    mat4f pMat = mat4f(pMatd);

    GLuint    vertexArrayObject;

    GLuint    positionBufferObject;
    GLuint    colorBufferObject;
    GLuint    uvBufferObject;

    GLint     positionVertexAttribLocation;
    GLint     colorVertexAttribLocation;
    GLint     uvVertexAttribLocation;

    GLuint    texUniformLocation;

    GLuint    modelViewMatrixUniformLocation;
    GLuint    projectionMatrixUniformLocation;

    shaderProgram.use();

    modelViewMatrixUniformLocation = shaderProgram.getUniformLocation("viewMatrix");
    projectionMatrixUniformLocation = shaderProgram.getUniformLocation("projMatrix");
    texUniformLocation = shaderProgram.getUniformLocation("tex");

    glUniformMatrix4fv(modelViewMatrixUniformLocation, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fv(projectionMatrixUniformLocation, 1, GL_TRUE, pMat.value_ptr);

    positionVertexAttribLocation = shaderProgram.getAttribLocation("position");
    colorVertexAttribLocation = shaderProgram.getAttribLocation("color");
    uvVertexAttribLocation = shaderProgram.getAttribLocation("uvV");

    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &positionBufferObject);
    glGenBuffers(1, &colorBufferObject);
    glGenBuffers(1, &uvBufferObject);

    glBindVertexArray(vertexArrayObject);

    glBindBuffer(GL_ARRAY_BUFFER, positionBufferObject);
    glBufferData(GL_ARRAY_BUFFER, positions.length * double.sizeof, positions.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(positionVertexAttribLocation);
    glVertexAttribPointer(positionVertexAttribLocation, 3, GL_DOUBLE, 0, 0, null);

    if (colorVertexAttribLocation >= 0)
    {
      glBindBuffer(GL_ARRAY_BUFFER, colorBufferObject);
      glBufferData(GL_ARRAY_BUFFER, colors.length * float.sizeof, colors.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArray(colorVertexAttribLocation);
      glVertexAttribPointer(colorVertexAttribLocation, 3, GL_FLOAT, 0, 0, null);
    }

    if (uvVertexAttribLocation >= 0)
    {
      glBindBuffer(GL_ARRAY_BUFFER, uvBufferObject);
      glBufferData(GL_ARRAY_BUFFER, UVs.length * double.sizeof, UVs.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArray(uvVertexAttribLocation);
      glVertexAttribPointer(uvVertexAttribLocation, 2, GL_DOUBLE, 0, 0, null);
    }

    if (texUniformLocation >= 0 && myTex !is null)
    {
      glActiveTexture(GL_TEXTURE0); 
      glBindTexture(GL_TEXTURE_2D, myTex.v);
      glUniform1i(texUniformLocation, 0);
      //glActiveTexture(GL_TEXTURE1); 
      //glBindTexture(GL_TEXTURE_2D, texture1);
      //glUniform1i(_textureUniform, 1);
    }

    glDrawArrays(GL_TRIANGLES, 0, numVerts);

    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffers(1, &positionBufferObject);
    glDeleteBuffers(1, &colorBufferObject);
    glDeleteBuffers(1, &uvBufferObject);

    positions.length = 0;
    colors.length = 0;
    UVs.length = 0;
    numVerts = 0;
  }
}
