#----------------------------------------------------------
# File hello.py
#----------------------------------------------------------
import bpy, bmesh

def selectedFaces(bm):
  return filter(lambda fa: fa.select, bm.faces)

def getEditMesh(cx):
  if cx.mode == 'EDIT_MESH':
      ob = cx.object
      if ob and ob.type == 'MESH' and ob.select:
        return bmesh.from_edit_mesh(ob.data)
  return None

#
#  Menu in window region, object context
#
class ObjectPanel(bpy.types.Panel):
  bl_label = "Escher (Object)"
  bl_space_type = "PROPERTIES"
  bl_region_type = "WINDOW"
  bl_context = "object"
 
  def draw(self, context):
    print('eschertools.ObjectPanel.draw()')
    self.layout.operator("hello.hello", text='Bonjour').country = "France"

    print('context: ', context)
    print('bpy.context: ', bpy.context)
    me = getEditMesh(context)
    if me:
      print('found active mesh')
      fa = list(selectedFaces(me))
      if len(fa):
        print('found selected faces', list(map(lambda f:'%s select=%s' % (f, f.select), fa)))
        self.layout.operator("hello.hello", text='Hello').country = "USA"

#
#  Menu in window region, material context
#
class MaterialPanel(bpy.types.Panel):
  bl_label = "Escher (Material)"
  bl_space_type = "PROPERTIES"
  bl_region_type = "WINDOW"
  bl_context = "material"
 
  def draw(self, context):
    self.layout.operator("hello.hello", text='Ciao').country = "Italy"
 
#
#  The Hello button prints a message in the console
#
class OBJECT_OT_HelloButton(bpy.types.Operator):
  bl_idname = "hello.hello"
  bl_label = "Say Hello"
  country = bpy.props.StringProperty()

  def execute(self, context):
    print('OBJECT_OT_HelloButton() context: ', context)
    for k in dir(context):
      print('context.', k, ' = ', getattr(context, k))
    if self.country == '':
      print("Hello world!")
    else:
      print("Hello world from %s!" % self.country)
    return{'FINISHED'}  
 
#
#	Registration
#   All panels and operators must be registered with Blender; otherwise
#   they do not show up. The simplest way to register everything in the
#   file is with a call to bpy.utils.register_module(__name__).
#
 
bpy.utils.register_module(__name__)
