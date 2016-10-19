# Escher

This was an experiment in non-Euclidean gaming, inspired by the works of M.C.
Escher.

I'm mostly putting this on github because I don't want to lose the work and
I'd like to share it with others for kicks.

In Escher, there is no world space.

There is only local-world space. Pieces of the world are expressed in familiar
Euclidean 3D space, but those pieces are related to each other by arbitrary
affine transforms, through designated polygons in the collision mesh.

In this version, there is no separation between collision mesh and visible
world geometry. Sorry, hopefully I'll find time to add it.

Some simple fun demos can be made very quickly in Blender, like an endless
tunnel, etc.

IIRC there is some bug that causes some orientation changes in the transform
to not work quite correctly.

I think another issue is in the way that visibility of "adjacent spaces"
(often called "remote spaces" or just "remotes" in the code IIRC) is
calculated. I only had OpenGL 3.3 at the time and there were some OpenGL
features I don't think I had access to which might have provided a faster
(and more accurate!) alternative implementation of this particular feature.

Escher uses its own map file format which can be exported from Blender using
the "Escher Tools" Blender plug-in (extension? addon? I don't remember
Blender's terminology.)

Escher Tools (ET hereafter) represent "spaces" (the Euclidean chunks of the
map) as Blender objects. Special objects parented to those objects represent
"adjacent" spaces (spaces directly reachable from a given space) and the
transform that relates one to the other (the relationship is not necessarily
reciprocated!)

Apparently I've posted that part some time ago here:
https://gist.github.com/hdon/5a30ab20bd35e1315c07

ET gives you some extra editor functions to make navigating and building a
non-Euclidean map easier. 

One button will create temporary mesh objects representing adjacent spaces
called IIRC "SSOs" or "Secondary Space Objects" to distinguish them from the
"Primary Space Objects" from which they borrow their mesh data.

This way you can "rez out" a limited view of the non-Euclidean world: however
much your brain can handle, or however much is useful to you.

A few other buttons control designating mesh faces as "portals" to an adjacent
space.

All the physics in the game is written by hand and is a little crappy, but
sufficient for the experiment, and was a good exercise to write.

I'll try to get a real git repo for it, soon.

I also wrote a Quake MD5 skeletal model renderer for this. The faster renderer
can be used with up to four weights per vertex. Beyond that and you can't
calculate vertexes in the vertex shader and you have to use the slow renderer.

I'll write more here when I get more time.
