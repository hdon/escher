import bpy, bmesh
from mathutils import Color

def selectedFaces(bm):
  return filter(lambda fa: fa.select, bm.faces)

def getEditMesh(cx):
  if cx.mode == 'EDIT_MESH':
      ob = cx.object
      if ob and ob.type == 'MESH' and ob.select:
        return bmesh.from_edit_mesh(ob.data)
  return None

def getPortalMaterial():
  if 'EscherPortalMaterial' in bpy.data.materials:
    return bpy.data.materials['EscherPortalMaterial']
  mat = bpy.data.materials.new('EscherPortalMaterial')
  mat.diffuse_color = Color((1,0,1))
  mat.use_transparency = True
  mat.alpha = 0.5
  return mat

class OBJECT_OT_NewSpaceButton(bpy.types.Operator):
  bl_idname = 'escher.create_space'
  bl_label = 'New Space'
  
  def execute(self, cx):
    # Create a new mesh representing the Esher space
    # Create a new PSO (Primary Space Object) containing the mesh
    # Insert PSO into scene
    # If an EMPTY representing an Escher Remote is active
    #   hide PSO
    #   create SSO (Secondary Space Object) and parent to the EMPTY
    return {'FINISHED'}
    
class OBJECT_OT_HelloButton(bpy.types.Operator):
  bl_idname = "hello.hello"
  bl_label = "Say Hello"
  country = bpy.props.StringProperty()

  def execute(self, context):
    return{'FINISHED'}  
 
def getMeshMaterial(me, mat):
  '''Gets the index of a material in a mesh, and returns it.
     If it is not already a material of the mesh, it is added.'''
  if mat.name in me.materials:
    return me.materials.find(mat.name)
  rval = len(me.materials)
  me.materials.append(mat)
  return rval

class ESCHER_OT_Portalize_Face(bpy.types.Operator):
  '''Portalize selected faces'''
  bl_idname = "escher.portalize_face"
  bl_label = "Portalize Mesh Face"
  
  def execute(self, cx):
    mat = getPortalMaterial()
    me = cx.object.data
    imat = getMeshMaterial(me, mat)
    bm = getEditMesh(cx)
    if bm:
      for fa in selectedFaces(bm):
        fa.material_index = imat
    self.report({'INFO'}, 'Portalized face materials!')
    return {'FINISHED'}
  
  @classmethod
  def poll(cls, cx):
    me = getEditMesh(cx)
    if me:
      fa = list(selectedFaces(me))
      if len(fa):
        return True
    return False

class ESCHER_OT_LinkRemote(bpy.types.Operator):
  '''Links a remote space to this one'''
  bl_idname = "escher.link_remote"
  bl_label = "Link Remote"
  
  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT' and cx.object and cx.object.type == 'MESH'

  def execute(self, cx):
    # This empty object represents the remote space
    eo = bpy.data.objects.new('EscherRemote', None)
    cx.scene.objects.link(eo)
    eo['escher_remote_space_name'] = '*none*'
    eo.parent = cx.object
    bpy.ops.object.select_all(action='DESELECT')
    eo.select = True
    bpy.ops.transform.translate()
    return bpy.ops.transform.translate('INVOKE_DEFAULT')

class ESCHER_OT_RealizeRemote(bpy.types.Operator):
  '''Creates an object parented to the symbolic EMPTY object representing an Escher Remote.
  
  The object created is referred to as an SSO, or "Secondary Space Object." This object is
  disposable and probably won't get saved in the .blend file. The PSO, or "Primary Space
  Object," is not expendable, as it has children which are important, and of course its
  data is the mesh representing the geometry of the Escher Space.'''
  
  bl_idname = 'escher.realize_remote'
  bl_label = 'Realize Remote'

  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT' and cx.object and cx.object.type == 'EMPTY' and \
        'escher_remote_space_name' in cx.object

  def execute(self, cx):
    eo = cx.object
    for child in eo.children:
      if child.name.startswith('EscherSSO_'):
        showGraph(child)
        return {'FINISHED'}
    remoteSpaceName = eo['escher_remote_space_name']
    sso = makeSSO(remoteSpaceName)
    cx.scene.objects.link(sso)
    sso.parent = eo
    # TODO lock all transforms of the SSO
    return {'FINISHED'}

class EscherSelectRemote(bpy.types.Operator):
  """Select a remote space to be linked"""
  bl_idname = "escher.select_remote"
  bl_label = "Select Remote"
  bl_options = {'REGISTER', 'UNDO'}
  bl_property = "enumprop"

  def item_cb(self, context):
    return [('*new*', 'New Space', '')] + [(c.name, c.name[10:], '') for c in self.choices]

  # This has to be a bpy.props.CollectionProperty(), it can't be a Python List!!!
  choices = bpy.props.CollectionProperty(type=bpy.types.PropertyGroup)
  enumprop = bpy.props.EnumProperty(items=item_cb)

  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT' and cx.object and cx.object.type == 'EMPTY' and \
        'escher_remote_space_name' in cx.object

  def execute(self, cx):
    if self.enumprop == '*new*':
      self.report({'INFO'}, 'TODO: Implement NEW')
      return {'FINISHED'}
    remotePsoName = self.enumprop
    remoteSpaceName = psoName2spaceName(remotePsoName)
    removeSsosFromRemoteEmpty(cx.object, cx)
    cx.object['escher_remote_space_name'] = remoteSpaceName
    return {'FINISHED'}

  def invoke(self, context, event):
    self.choices.clear()
    for ob in bpy.data.objects:
      if ob.name.startswith('EscherPSO_'):
        self.choices.add().name = ob.name
    context.window_manager.invoke_search_popup(self)
    return {'FINISHED'}

class EscherNewSpace(bpy.types.Operator):
  '''Create a new Escher Space, and focus on its PSO'''
  bl_idname = 'escher.new_space'
  bl_label = 'New Space'

  newSpaceName = bpy.props.StringProperty(name='Escher Space Name', description='Name your new space', default='Unnamed_Space')

  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT'

  def execute(self, cx):
    pso = makePSO(self.newSpaceName)
    cx.scene.objects.link(pso)
    self.report({'INFO'}, 'Created new Space, mesh, and PSO')
    return {'FINISHED'}
    
  def invoke(self, cx, ev):
    return cx.window_manager.invoke_props_dialog(self) 

def removeSsosFromRemoteEmpty(eo, cx):
  for o in eo.children:
    if isSsoName(o.name):
      cx.scene.unlink(o)

def makePSO(spaceName, me=None):
  if me is None:
    bm = bmesh.new()
    for x in -1, 1:
      for y in -1, 1:
        for z in -1, 1:
          bm.verts.new().co = (x, y, z)
    bm.verts.index_update()
    bm.faces.new((bm.verts[0], bm.verts[2], bm.verts[3], bm.verts[1]))
    bm.faces.new((bm.verts[4], bm.verts[5], bm.verts[7], bm.verts[6]))
    bm.faces.new((bm.verts[0], bm.verts[4], bm.verts[6], bm.verts[2]))
    bm.faces.new((bm.verts[1], bm.verts[3], bm.verts[7], bm.verts[5]))
    bm.faces.new((bm.verts[0], bm.verts[1], bm.verts[5], bm.verts[4]))
    bm.faces.new((bm.verts[2], bm.verts[6], bm.verts[7], bm.verts[3]))
    me = bpy.data.meshes.new(spaceName2meshName(spaceName))
    # Assign default material (makes life easier)
    me.materials.append(bpy.data.materials['Material'])
    bm.to_mesh(me)
  pso = bpy.data.objects.new(spaceName2psoName(spaceName), me)
  pso.show_transparent = True
  return pso

def makeSSO(spaceName):
  psoName = spaceName2psoName(spaceName)
  if psoName not in bpy.data.objects:
    raise KeyError('Could not find "%s"' % psoName)
  ssoName = spaceName2ssoName(spaceName)
  sso = bpy.data.objects.new(ssoName, bpy.data.objects[psoName].data)
  sso.show_transparent = True
  return sso

def isUnqualifiedSpaceName(spaceName):
  return not (spaceName.startswith('EscherPSO_') or spaceName.startswith('EscherSSO_') or spaceName.startswith('EscherSM_'))

def toUnqualifiedSpaceName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return spaceName
  return spaceName[spaceName.find('_')+1:]

def spaceName2meshName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherSM_' + spaceName
  raise ValueError('Invalid space name!')

def spaceName2psoName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherPSO_' + spaceName
  raise ValueError('Invalid space name!')

def spaceName2ssoName(spaceName):
  if isUnqualifiedSpaceName(spaceName):
    return 'EscherSSO_' + spaceName
  raise ValueError('Invalid space name!')

def psoName2spaceName(psoName):
  if psoName.startswith('EscherPSO_'):
    return psoName[10:]
  else:
    raise ValueError('Invalid Escher PSO name string')

class EscherFocusSpace(bpy.types.Operator):
  '''Focus on a space by hiding all other spaces and displaying one space's PPO'''
  bl_idname = 'escher.focus_space'
  bl_label = 'Focus Space'
  bl_property = "enumprop"

  def item_cb(self, cx):
    rval = [(c.name, c.name[10:], '') for c in self.choices]
    if cx.object:
      rval = [('*current*', 'Currently Selected Object', '')] + rval
    return rval

  # This has to be a bpy.props.CollectionProperty(), it can't be a Python List!!!
  choices = bpy.props.CollectionProperty(type=bpy.types.PropertyGroup)
  enumprop = bpy.props.EnumProperty(items=item_cb)

  @classmethod
  def poll(cls, cx):
    return cx.mode == 'OBJECT'

  def execute(self, cx):
    if self.enumprop == '*current*':
      psoName = spaceName2psoName(toUnqualifiedSpaceName(cx.object.name))
    else:
      psoName = self.enumprop

    for ob in cx.scene.objects:
      if ob.type == 'MESH':
        hideGraph(ob)

    pso = bpy.data.objects[psoName]
    showGraph(pso)
    return {'FINISHED'}

  def invoke(self, context, event):
    self.choices.clear()
    for ob in bpy.data.objects:
      if ob.name.startswith('EscherPSO_'):
        self.choices.add().name = ob.name
    context.window_manager.invoke_search_popup(self)
    return {'FINISHED'}

def showGraph(ob):
  hideGraph(ob, False)

def hideGraph(ob, hide=True):
  ob.hide = hide
  for o in ob.children:
    hideGraph(o, hide)

class NPanel(bpy.types.Panel):
  bl_label = 'Escher Tools'
  bl_space_type = 'VIEW_3D'
  bl_region_type = 'TOOLS'
  
  def draw(self, cx):
    layout = self.layout
    layout.operator('escher.portalize_face')
    layout.operator('escher.link_remote')
    layout.operator('escher.realize_remote')
    layout.operator('mesh.flip_normals', text='Flip Normals')
    layout.operator('escher.select_remote')
    layout.operator('escher.new_space')
    layout.operator('escher.focus_space')

def register():
  #bpy.types.Object.escher_space_name = bpy.props.EnumProperty(items=escher_space_names)
  bpy.utils.register_module(__name__)

def unregister():
  #del bpy.types.Object.escher_space_name
  bpy.utils.unregister_module(__name__)

if __name__ == '__main__':
  register()
