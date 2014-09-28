all : client

include configuration.mak

CLIENT_SOURCES=src/ants/ascii.d src/ants/doglconsole.d src/ants/material.d src/ants/md5.d src/ants/shader.d src/ants/texture.d src/ants/escher.d src/ants/glutil.d src/ants/entity.d src/ants/hudtext.d src/ants/screen.d src/ants/vertexer.d src/ants/vbo.d src/ants/commands.d src/ants/rescache2.d src/ants/gametime.d src/ants/net.d src/ants/client.d src/gl3n/aabb.d src/gl3n/interpolate.d src/gl3n/ext/matrixstack.d src/gl3n/ext/hsv.d src/gl3n/frustum.d src/gl3n/linalg.d src/gl3n/math.d src/gl3n/util.d src/gl3n/plane.d src/ants/util.d

client : $(CLIENT_SOURCES)
	$(DC) -o $@ $^ $(DFLAGS) $(LDFLAGS)
