module ants.vertexer;
import ants.shader;
import gl3n.linalg : Vector, Matrix;
import derelict.opengl3.gl3;

private alias Vector!(double, 3) vec3d;
private alias Vector!(float, 3) vec3f;
alias Matrix!(double, 4, 4) mat4d;
alias Matrix!(float, 4, 4) mat4f;

class Vertexer
{
  double[]  positions;
  float[]   colors;
  uint      numVerts;

  this()
  {
  }

  void add(vec3d pos, vec3f color)
  {
    positions ~= pos.x;
    positions ~= pos.y;
    positions ~= pos.z;
    colors ~= color.x;
    colors ~= color.y;
    colors ~= color.z;
    numVerts++;
  }

  void draw(ShaderProgram shaderProgram, mat4d mvMatd, mat4d pMatd)
  {
    // XXX
    mat4f mvMat = mat4f(mvMatd);
    mat4f pMat = mat4f(pMatd);

    GLuint    vertexArrayObject;
    GLuint    positionBufferObject;
    GLuint    colorBufferObject;
    GLuint    positionVertexAttribLocation;
    GLuint    colorVertexAttribLocation;
    GLuint    modelViewMatrixUniformLocation;
    GLuint    projectionMatrixUniformLocation;

    modelViewMatrixUniformLocation = shaderProgram.getUniformLocation("viewMatrix");
    projectionMatrixUniformLocation = shaderProgram.getUniformLocation("projMatrix");

    glUniformMatrix4fv(modelViewMatrixUniformLocation, 1, GL_TRUE, mvMat.value_ptr);
    glUniformMatrix4fv(projectionMatrixUniformLocation, 1, GL_TRUE, pMat.value_ptr);

    positionVertexAttribLocation = shaderProgram.getAttribLocation("position");
    colorVertexAttribLocation = shaderProgram.getAttribLocation("color");

    glGenVertexArrays(1, &vertexArrayObject);
    glGenBuffers(1, &positionBufferObject);
    glGenBuffers(1, &colorBufferObject);

    glBindVertexArray(vertexArrayObject);

    glBindBuffer(GL_ARRAY_BUFFER, positionBufferObject);
    glBufferData(GL_ARRAY_BUFFER, positions.length * double.sizeof, positions.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(positionVertexAttribLocation);
    glVertexAttribPointer(positionVertexAttribLocation, 3, GL_DOUBLE, 0, 0, null);

    glBindBuffer(GL_ARRAY_BUFFER, colorBufferObject);
    glBufferData(GL_ARRAY_BUFFER, colors.length * double.sizeof, colors.ptr, GL_STREAM_DRAW);
    glEnableVertexAttribArray(colorVertexAttribLocation);
    glVertexAttribPointer(colorVertexAttribLocation, 3, GL_FLOAT, 0, 0, null);

    glDrawArrays(GL_TRIANGLES, 0, numVerts);

    glDeleteVertexArrays(1, &vertexArrayObject);
    glDeleteBuffers(1, &positionBufferObject);
    glDeleteBuffers(1, &colorBufferObject);

    positions.length = 0;
    colors.length = 0;
    numVerts = 0;
  }
}
