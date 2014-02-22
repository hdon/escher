/* Copyright 2014 Donny Viszneki. All rights reserved.
 * You are not authorized to distribute this source code.
 */
module ants.vertexer;
import ants.shader;
import gl3n.linalg : Vector, Matrix;
//import derelict.opengl3.gl3;
import glad.gl.all;
import ants.texture;
import ants.material;

private alias Vector!(double, 3) vec3d;
private alias Vector!(double, 2) vec2d;
private alias Vector!(float, 3) vec3f;
private alias Vector!(float, 2) vec2f;
alias Matrix!(double, 4, 4) mat4d;
alias Matrix!(float, 4, 4) mat4f;
alias Matrix!(float, 3, 3) mat3f;

class Vertexer
{
  vec3d []  positions;
  vec2d []  UVs;
  vec3f []  colors;
  vec3d []  normals;
  uint      numVerts;
  vec3f     lightPos;

  static
  {
    float   frameTime;
    vec2f   resolution;
    void setFrameTime(float t)
    {
      frameTime = t;
    }
    void setResolution(float x, float y)
    {
      resolution = vec2f(x, y);
    }
  }

  this()
  {
    lightPos = vec3f(1,0,0);
    positions.length = 2;
    colors.length    = 2;
    UVs.length       = 2;
    normals.length   = 2;
  }

  void add(vec3d pos, vec2d uv, vec3d normal, vec3f color)
  {
    if (positions.length <= numVerts)
    {
      positions.length *= 2;
      colors.length *= 2;
      UVs.length *= 2;
      normals.length *= 2;
    }

    positions[numVerts] = pos;
    colors[numVerts] = color;
    UVs[numVerts] = uv;
    normals[numVerts] = normal;
    numVerts++;
  }

  vec3f pointLightPos;

  void draw(ShaderProgram shaderProgram, mat4d mvMatd, mat4d pMatd, Material material, GLenum mode=GL_TRIANGLES)
  {
    GLuint colorMap;
    GLuint normalMap;

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

    GLuint    timeUniformLocation;
    GLuint    resolutionUniformLocation;

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
    glUniformMatrix4fvARB(modelViewMatrixUniformLocation, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fvARB(projectionMatrixUniformLocation, 1, GL_TRUE, pMat.value_ptr);
    glUniformMatrix3fvARB(normalMatrixUniformLocation, 1, GL_TRUE, normalMat.value_ptr);

    /* Send light uniform values */
    glUniform3fARB(lightSourceUniformLocation_pos, lightPos.x, lightPos.y, lightPos.z);
    glUniform4fARB(lightSourceUniformLocation_diffuse, 1, 1, 1, 1);
    glUniform4fARB(lightSourceUniformLocation_specular, 1, 1, 1, 1);

    /* Miscellanious uniform values */
    timeUniformLocation = shaderProgram.getUniformLocation("time");
    resolutionUniformLocation = shaderProgram.getUniformLocation("resolution");

    if (timeUniformLocation >= 0)
      glUniform1fARB(timeUniformLocation, frameTime);

    if (resolutionUniformLocation >= 0)
      glUniform2fARB(resolutionUniformLocation, resolution.x, resolution.y);

    /* Get vertex attribute locations */
    positionVertexAttribLocation = shaderProgram.getAttribLocation("positionV");
    colorVertexAttribLocation = shaderProgram.getAttribLocation("colorV");
    uvVertexAttribLocation = shaderProgram.getAttribLocation("uvV");
    normalVertexAttribLocation = shaderProgram.getAttribLocation("normalV");

    /* Generate arrays/buffers to send vertex data */
    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffersARB(1, &positionBufferObject);
    glGenBuffersARB(1, &colorBufferObject);
    glGenBuffersARB(1, &uvBufferObject);
    glGenBuffersARB(1, &normalBufferObject);

    /* Send vertex data */
    glBindVertexArray(vertexArrayObject);

    glBindBufferARB(GL_ARRAY_BUFFER, positionBufferObject);
    glBufferDataARB(GL_ARRAY_BUFFER, numVerts * vec3d.sizeof, positions.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArrayARB(positionVertexAttribLocation);
    glVertexAttribPointerARB(positionVertexAttribLocation, 3, GL_DOUBLE, 0, 0, null);

    if (colorVertexAttribLocation >= 0)
    {
      glBindBufferARB(GL_ARRAY_BUFFER, colorBufferObject);
      glBufferDataARB(GL_ARRAY_BUFFER, numVerts * vec3f.sizeof, colors.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArrayARB(colorVertexAttribLocation);
      glVertexAttribPointerARB(colorVertexAttribLocation, 3, GL_FLOAT, 0, 0, null);
    }

    if (uvVertexAttribLocation >= 0)
    {
      glBindBufferARB(GL_ARRAY_BUFFER, uvBufferObject);
      glBufferDataARB(GL_ARRAY_BUFFER, numVerts * vec2d.sizeof, UVs.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArrayARB(uvVertexAttribLocation);
      glVertexAttribPointerARB(uvVertexAttribLocation, 2, GL_DOUBLE, 0, 0, null);
    }

    if (normalVertexAttribLocation >= 0)
    {
      glBindBufferARB(GL_ARRAY_BUFFER, normalBufferObject);
      glBufferDataARB(GL_ARRAY_BUFFER, numVerts * vec3d.sizeof, normals.ptr, GL_STREAM_DRAW);
      glEnableVertexAttribArrayARB(normalVertexAttribLocation);
      glVertexAttribPointerARB(normalVertexAttribLocation, 3, GL_DOUBLE, 0, 0, null);
    }

    int texCounter = 0;

    if (colorMapUniformLocation >= 0)
    {
      glActiveTexture(GL_TEXTURE0 + texCounter);
      glBindTexture(GL_TEXTURE_2D, colorMap);
      glUniform1iARB(colorMapUniformLocation, texCounter++);
    }
    if (normalMapUniformLocation >= 0)
    {
      glActiveTexture(GL_TEXTURE0 + texCounter);
      glBindTexture(GL_TEXTURE_2D, normalMap);
      glUniform1iARB(normalMapUniformLocation, texCounter++);
    }

    glDrawArrays(mode, 0, numVerts);

    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffersARB(1, &positionBufferObject);
    glDeleteBuffersARB(1, &colorBufferObject);
    glDeleteBuffersARB(1, &uvBufferObject);
    glDeleteBuffersARB(1, &normalBufferObject);

    numVerts = 0;
  }
}

Vertexer vertexer;
