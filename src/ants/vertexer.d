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
  double[]  normals;
  uint      numVerts;

  this()
  {
  }

  void add(vec3d pos, vec2d uv, vec3d normal, vec3f color)
  {
    positions ~= pos.x;
    positions ~= pos.y;
    positions ~= pos.z;
    colors ~= color.x;
    colors ~= color.y;
    colors ~= color.z;
    UVs ~= uv.x;
    UVs ~= uv.y;
    normals ~= normal.x;
    normals ~= normal.y;
    normals ~= normal.z;
    numVerts++;
  }

  vec3f pointLightPos;

  void draw(ShaderProgram shaderProgram, mat4d mvMatd, mat4d pMatd, Material material)
  {
    Texture myTex;
    if (material !is null)
      myTex = material.texes[0].texture; // XXX

    // XXX
    mat4f mvMat = mat4f(mvMatd);
    mat4f pMat = mat4f(pMatd);
    mat4f normalMat = mat4f(mvMat[0][0], mvMat[0][1], mvMat[0][2],
                            mvMat[1][0], mvMat[1][1], mvMat[1][2],
                            mvMat[2][0], mvMat[2][1], mvMat[2][2]);

    GLuint    vertexArrayObject;

    GLuint    positionBufferObject;
    GLuint    colorBufferObject;
    GLuint    uvBufferObject;
    GLuint    normalBufferObject;

    GLint     positionVertexAttribLocation;
    GLint     colorVertexAttribLocation;
    GLint     uvVertexAttribLocation;
    GLint     normalVertexAttribLocation;

    GLuint    texUniformLocation;

    GLuint    modelViewMatrixUniformLocation;
    GLuint    projectionMatrixUniformLocation;
    GLuint    normalMatrixUniformLocation;
    GLuint    pointLightPosUniformLocation;

    shaderProgram.use();

    modelViewMatrixUniformLocation = shaderProgram.getUniformLocation("viewMatrix");
    projectionMatrixUniformLocation = shaderProgram.getUniformLocation("projMatrix");
    normalMatrixUniformLocation = shaderProgram.getUniformLocation("normalMatrix");
    texUniformLocation = shaderProgram.getUniformLocation("tex");
    pointLightPosUniformLocation = shaderProgram.getUniformLocation("pointLightPos");

    glUniformMatrix4fv(modelViewMatrixUniformLocation, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fv(projectionMatrixUniformLocation, 1, GL_TRUE, pMat.value_ptr);
    glUniformMatrix3fv(normalMatrixUniformLocation, 1, GL_TRUE, normalMat.value_ptr);
    glUniform3f(pointLightPosUniformLocation, 0, 0, 0);

    positionVertexAttribLocation = shaderProgram.getAttribLocation("positionV");
    colorVertexAttribLocation = shaderProgram.getAttribLocation("colorV");
    uvVertexAttribLocation = shaderProgram.getAttribLocation("uvV");
    normalVertexAttribLocation = shaderProgram.getAttribLocation("normalV");

    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &positionBufferObject);
    glGenBuffers(1, &colorBufferObject);
    glGenBuffers(1, &uvBufferObject);
    glGenBuffers(1, &normalBufferObject);

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

    if (normalVertexAttribLocation >= 0)
    {
      glBindBuffer(GL_ARRAY_BUFFER, normalBufferObject);
      glBufferData(GL_ARRAY_BUFFER, normals.length * double.sizeof, normals.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArray(normalVertexAttribLocation);
      glVertexAttribPointer(normalVertexAttribLocation, 3, GL_DOUBLE, 0, 0, null);
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
    glDeleteBuffers(1, &normalBufferObject);

    positions.length = 0;
    colors.length = 0;
    UVs.length = 0;
    normals.length = 0;
    numVerts = 0;
  }
}
