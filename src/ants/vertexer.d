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
alias Matrix!(float, 3, 3) mat3f;

class Vertexer
{
  double[]  positions;
  double[]  UVs;
  float[]   colors;
  double[]  normals;
  uint      numVerts;
  vec3f     lightPos;

  this()
  {
    lightPos = vec3f(1,0,0);
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
    Texture colorMap;
    Texture normalMap;

    if (material !is null)
    {
      foreach (matTex; material.texes)
      {
        switch (matTex.application)
        {
          case TextureApplication.Color:
            colorMap = matTex.texture;
            break;
          case TextureApplication.Normal:
            normalMap = matTex.texture;
            break;
          default:
            assert(0, "invalid texture application");
            break;
        }
      }
    }

    // XXX
    mat4f mvMat = mat4f(mvMatd);
    mat4f pMat = mat4f(pMatd);
    mat3f normalMat = mat3f(mvMat.rotation);
    //mat3f normalMat = mat3f(mvMat[0][0], mvMat[1][0], mvMat[2][0],
                            //mvMat[0][1], mvMat[1][1], mvMat[2][1],
                            //mvMat[0][2], mvMat[1][2], mvMat[2][2]);
    //writeln("mvmat: ", normalMat);

    GLuint    vertexArrayObject;

    GLuint    positionBufferObject;
    GLuint    colorBufferObject;
    GLuint    uvBufferObject;
    GLuint    normalBufferObject;

    GLint     positionVertexAttribLocation;
    GLint     colorVertexAttribLocation;
    GLint     uvVertexAttribLocation;
    GLint     normalVertexAttribLocation;

    GLuint    colorMapUniformLocation;
    GLuint    normalMapUniformLocation;

    GLuint    modelViewMatrixUniformLocation;
    GLuint    projectionMatrixUniformLocation;
    GLuint    normalMatrixUniformLocation;

    GLuint    lightSourceUniformLocation_pos;
    GLuint    lightSourceUniformLocation_diffuse;
    GLuint    lightSourceUniformLocation_specular;

    shaderProgram.use();

    /* Get matrix uniform locations */
    modelViewMatrixUniformLocation = shaderProgram.getUniformLocation("viewMatrix");
    projectionMatrixUniformLocation = shaderProgram.getUniformLocation("projMatrix");
    normalMatrixUniformLocation = shaderProgram.getUniformLocation("normalMatrix");

    /* Get texture uniform locations */
    colorMapUniformLocation = shaderProgram.getUniformLocation("colorMap");
    normalMapUniformLocation = shaderProgram.getUniformLocation("normalMap");

    /* Get light source uniform locations */
    lightSourceUniformLocation_pos = shaderProgram.getUniformLocation("lightSource.pos");
    lightSourceUniformLocation_diffuse = shaderProgram.getUniformLocation("lightSource.diffuse");
    lightSourceUniformLocation_specular = shaderProgram.getUniformLocation("lightSource.specular");

    /* Send matrix uniform values */
    glUniformMatrix4fv(modelViewMatrixUniformLocation, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fv(projectionMatrixUniformLocation, 1, GL_TRUE, pMat.value_ptr);
    glUniformMatrix3fv(normalMatrixUniformLocation, 1, GL_TRUE, normalMat.value_ptr);

    /* Send light uniform values */
    glUniform3f(lightSourceUniformLocation_pos, lightPos.x, lightPos.y, lightPos.z);
    glUniform4f(lightSourceUniformLocation_diffuse, 1, 0, 0, 1);
    glUniform4f(lightSourceUniformLocation_specular, 0, 1, 1, 1);

    /* Get vertex attribute locations */
    positionVertexAttribLocation = shaderProgram.getAttribLocation("positionV");
    colorVertexAttribLocation = shaderProgram.getAttribLocation("colorV");
    uvVertexAttribLocation = shaderProgram.getAttribLocation("uvV");
    normalVertexAttribLocation = shaderProgram.getAttribLocation("normalV");

    /* Generate arrays/buffers to send vertex data */
    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &positionBufferObject);
    glGenBuffers(1, &colorBufferObject);
    glGenBuffers(1, &uvBufferObject);
    glGenBuffers(1, &normalBufferObject);

    /* Send vertex data */
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

    int texCounter = 0;

    if (colorMapUniformLocation >= 0 && colorMap !is null)
    {
      glActiveTexture(GL_TEXTURE0 + texCounter);
      glBindTexture(GL_TEXTURE_2D, colorMap.v);
      glUniform1i(colorMapUniformLocation, texCounter++);
    }
    if (normalMapUniformLocation >= 0 && normalMap !is null)
    {
      glActiveTexture(GL_TEXTURE0 + texCounter);
      glBindTexture(GL_TEXTURE_2D, normalMap.v);
      glUniform1i(normalMapUniformLocation, texCounter++);
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
