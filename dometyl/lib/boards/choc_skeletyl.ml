(** A lower profile skeletyl, with curvatures adjusted for chocs, and bumpon
    eyelets built in to the case. *)

open! Base
open! Scad_ml
open Generator

let lookups =
  let offset = function
    | 2 -> 0., 3.5, -8. (* middle *)
    | 3 -> 0., -1., -1.5 (* ring *)
    | i when i >= 4 -> 0., -12., 7. (* pinky *)
    | 0 -> -0.75, 0., 0.
    | _ -> 0., 0., -3.
  and curve = function
    | 0 ->
      Curvature.(
        curve ~well:(spec ~radius:57. (Float.pi /. 9.) ~tilt:(Float.pi /. 11.)) ())
    | _ -> Curvature.(curve ~well:(spec ~radius:56.5 (Float.pi /. 9.)) ())
  and swing = function
    | 2 -> Float.pi /. -48.
    | 3 -> Float.pi /. -19.
    | 4 -> Float.pi /. -14.
    | _ -> 0.
  and splay _ = 0.
  and rows _ = 3 in
  Plate.Lookups.make ~offset ~curve ~splay ~swing ~rows ()

let plate_builder =
  Plate.make
    ~n_cols:5
    ~spacing:0.5
    ~tent:(Float.pi /. 10.)
    ~lookups
    ~thumb_offset:(-1., -49., -6.)
    ~thumb_angle:Float.(0., pi /. -4.3, pi /. 6.)
    ~thumb_curve:
      Curvature.(curve ~fan:{ angle = Float.pi /. 14.5; radius = 85.; tilt = 0. } ())
    ~caps:Caps.MBK.uniform

let plate_welder = Plate.skeleton_bridges
let screw_config = Screw.{ bumpon_config with hole = Inset 0.8 }

let wall_builder plate =
  Walls.
    { body =
        Body.make
          ~n_steps:(`Flat 3)
          ~n_facets:5
          ~north_clearance:1.5
          ~south_clearance:1.5
          ~side_clearance:1.5
          ~screw_config
          plate
    ; thumb =
        Thumb.make
          ~south_lookup:(fun i -> if not (i = 1) then Yes else No)
          ~east:No
          ~west:Screw
          ~clearance:0.5
          ~d1:4.
          ~d2:4.75
          ~n_steps:(`PerZ 5.)
          ~n_facets:2
          ~screw_config
          plate
    }

let base_connector =
  Connect.skeleton
    ~height:5.
    ~thumb_height:9.
    ~east_link:(Connect.snake ~height:9. ~n_facets:3 ~scale:1.5 ~d:1. ())
    ~west_link:(Connect.cubic ~height:11. ~scale:1.25 ~d:1. ~bow_out:false ())
    ~cubic_d:2.
    ~cubic_scale:1.
    ~body_join_steps:3
    ~thumb_join_steps:3
    ~fudge_factor:8.
    ~close_thumb:false

let ports_cutter = BastardShield.(cutter ~x_off:(-2.) ~y_off:(-1.5) (make ()))

let build ?right_hand ?hotswap () =
  let keyhole = Choc.make_hole ~clearance:0. ?hotswap () in
  Case.make
    ?right_hand
    ~plate_builder
    ~plate_welder
    ~wall_builder
    ~base_connector
    ~ports_cutter
    keyhole

let bastard_compare () =
  Scad.union
    [ Skeletyl.bastard_skelly
    ; Case.to_scad ~show_caps:false (build ()) |> Scad.color ~alpha:0.5 Color.Yellow
    ]
