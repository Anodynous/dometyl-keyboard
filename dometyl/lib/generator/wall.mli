open! Base
open! Scad_ml

(** Configuration type for number of steps used to draw the bezier curves that
    form the walls. *)
module Steps : sig
  (** [`Flat n] simply indicates [n] steps, [`PerZ mm] specifies that there should
      be a step for every [mm] off the ground the start of the wall is. *)
  type t =
    [ `Flat of int
    | `PerZ of float
    ]

  (** [to_int t z]

      Converts to a discrete number of steps. In the case of `Flat, it is simply the
      contained integer and the z value will be ignored. For `PerZ, the resulting
      number of steps will be how many times the wrapped float fits into the provided
      z value. *)
  val to_int : [< `Flat of int | `PerZ of float ] -> float -> int
end

(** Bezier curve wall edge type and helpers. *)
module Edge : sig
  (** Bezier function, returns position along curve, from 0. to 1. *)
  type t = float -> Vec3.t

  (** Basic transformation functions *)
  include Sigs.Transformable with type t := t

  (** [point_at_z ?max_iter ?tolerance t z]

      Use {!Util.bisection_exn} to search for the {!Vec3.t} in [t] closest to
      [z]. [max_iter] and [tolerance] provide maximum iterations and tolerance
      (accuracy) bounds to the search function. *)
  val point_at_z : ?max_iter:int -> ?tolerance:float -> t -> float -> Vec3.t
end

(** Functions that find the point along the top and bottom edges of the start
    position of the wall closest to the given xy position, and provides a
    bezier edge to the ground starting from there. *)
module EdgeDrawer : sig
  type drawer = Vec3.t -> Edge.t

  type t =
    { top : drawer
    ; bot : drawer
    }

  val make
    :  ?max_iter:int
    -> ?tolerance:float
    -> get_bez:(bool -> Vec3.t -> Edge.t)
    -> Points.t
    -> t

  val map : f:(drawer -> drawer) -> t -> t

  (** Basic transformation functions *)
  include Sigs.Transformable with type t := t
end

(** Bezier curves representing the four edges running from the start to the foot
    of each {!Wall.t} *)
module Edges : sig
  (** Record containting an {!Edge.t} running from the corners of
      {!KeyHole.Face.points} down to the floor, where the terminal points are
      used for {!Wall.foot}. *)
  type t =
    { top_left : Edge.t
    ; top_right : Edge.t
    ; bot_left : Edge.t
    ; bot_right : Edge.t
    }

  val map : f:(Edge.t -> Edge.t) -> t -> t

  (** Basic transformation functions *)
  include Sigs.Transformable with type t := t

  (** [of_clockwise_list_exn l]
      Convert a four element list into a [t]. The ordering actually shouldn't just be
      clockwise, but is assumed to literally be: TL, TR, BR, BL. *)
  val of_clockwise_list_exn : Edge.t list -> t

  val of_clockwise_list : Edge.t list -> (t, string) Result.t

  (** [get t corner]

      Access fields from record [t] according to provided [corner] tag. *)
  val get : t -> [< `BL | `BR | `TL | `TR ] -> Edge.t
end

(** Record representing a wall extending from a {!KeyHole.Face.t} to the ground. *)
type t =
  { scad : Scad.t (** Aggregate scad, including screw outshoot if included *)
  ; start : Points.t (** Corner points of the {!KeyHole.Face.t} this wall emerged from *)
  ; foot : Points.t (** Terminal points where the wall meets the XY plane. *)
  ; edge_drawer : EdgeDrawer.t
        (** Generate {!Edge.t}'s emerging from point along top and bottom
        starting edges of the wall closest to the provided {!Vec3.t} on the XY
        plane. *)
  ; edges : Edges.t (** Bezier curves that specify the edge vertices. *)
  ; screw : Screw.t option
        (** Scad, coordinates, and config of screw offshoot if included. *)
  }

(** Basic transformation functions *)
include Sigs.Transformable with type t := t

(** [swing_face ?step key_orgin face]

    Iteratively find a rotation around [face]s bottom or top axis, depending on
    which way it is pointing in z (determined with [key_origin]), that brings
    [face] to a more vertical orientation, returning a pivoted {!KeyHole.Face.t}
    and it's new orthogonal {!Vec3.t}. *)
val swing_face : ?step:float -> Vec3.t -> KeyHole.Face.t -> KeyHole.Face.t * Vec3.t

(** [poly_siding ?x_off ?y_off ?z_off ?clearance ?n_steps ?n_facets ?d1 ?d2 ?thickness
      ?screw_config side keyhole]

Generate a {!type:t} using an OpenScad polyhedron, drawn from a set of bezier curves
from the [side] facing edges of [keyhole]. Optional parameters influence the shape of the
generated wall:
- [x_off] and [y_off] shift the target endpoints (on the ground) of the wall
- [z_off] shifts the second bezier control point in z (positive would lead to more arc)
- [clearance] moves the start of the wall out from the face of the keyhole
- [n_steps] controls the number of points used to draw the wall (see:
  {!module:Steps}). This impact the aeshetics of the wall, but it also
  determines how well the wall follows the bezier curve, which can have
  implications for positioning the cutouts for ports near the bottom of the
  case. A number of steps that is too high can sometimes cause the generated
  polyhedrons to fail, as points can bunch up, leading to a mesh that is
  difficult for the OpenScad engine (CGAL) to close. When this happens, either
  decreasing number of steps (can be done preferentially for short walls with
  `PerZ), or increasing [n_facets] to increase the number of (and decrease the
  size of) triangles that CGAL can use to close the wall shape.
- [n_facets] sets the number of polyhedron faces assigned to the outside and
  inside of the wall. Values above one will introduce additional beziers of
  vertices spaced between the ends of the wall, leading to a finer triangular mesh.
- [d1] and [d2] set the distance projected outward along the orthogonal of the [side]
  of the [keyhole] on the xy-plane used to for the second and third quadratic bezier
  control points respectively.
- [thickness] influences the thickness of the wall (from inside to outside face)
- If provided, [screw_config] describes the screw/bumpon eyelet that should be added
  to the bottom of the generated wall. *)
val poly_siding
  :  ?x_off:float
  -> ?y_off:float
  -> ?z_off:float
  -> ?clearance:float
  -> ?n_steps:[< `Flat of int | `PerZ of float > `Flat ]
  -> ?n_facets:int
  -> ?d1:float
  -> ?d2:float
  -> ?thickness:float
  -> ?screw_config:Screw.config
  -> [< `East | `North | `South | `West ]
  -> 'a KeyHole.t
  -> t

(** [column_drop ?z_off ?clearance ?n_steps ?n_facets ?d1 ?d2 ?thickness ?screw_config
      ~spacing ~columns idx]

    Wrapper function for {!val:poly_siding} specifically for (north and south)
    column end walls. Unlike {!val:poly_siding}, which takes a {!KeyHole.t},
    this takes the map [columns], and an [idx] specifying the column to generate
    the wall for. Overhang over the next column (to the right) that may have
    been introduced by tenting is checked for, and an x offset that will reclaim
    the desired column [spacing] is calculated and passed along to {!val:poly_siding}. *)
val column_drop
  :  ?z_off:float
  -> ?clearance:float
  -> ?n_steps:[< `Flat of int | `PerZ of float > `Flat ]
  -> ?n_facets:int
  -> ?d1:float
  -> ?d2:float
  -> ?thickness:float
  -> ?screw_config:Screw.config
  -> spacing:float
  -> columns:'k Columns.t
  -> [< `North | `South ]
  -> int
  -> t

(** [start_direction t]

    Direction vector from right to left of the wall start points. *)
val start_direction : t -> Vec3.t

(** [foot_direction t]

    Direction vector from right to left of the wall foot points. *)
val foot_direction : t -> Vec3.t

val to_scad : t -> Scad.t
