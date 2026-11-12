// airflow_plate.scad -- slip-on cap for the QNET-HVACT fan face (fan end ONLY, never the lamp end)
// Print three: open_frac = 1.0 (frame only, for fit check), 0.5 (disturbance / restricted
// airflow), 0.0 (fan-failure emulation). Export: F6 then File > Export > STL.
// Command line:  openscad -D open_frac=0.5 -o plate_50.stl airflow_plate.scad
//
// MEASURE YOUR FAN with calipers first and edit the two numbers below.

fan_outer = 60;    // [mm] outer width of the square fan housing (measure!)
fan_hole  = 56;    // [mm] diameter of the fan blade opening (measure!)
open_frac = 0.5;   // fraction of the blade opening left open (0.0 .. 1.0)

clear  = 0.6;      // [mm] slip-fit clearance per side (increase if too tight)
wall   = 2.0;      // [mm] sleeve wall
depth  = 8;        // [mm] how far the sleeve slides over the fan
face   = 2.0;      // [mm] face plate thickness
$fn    = 96;

inner = fan_outer + 2*clear;
outer = inner + 2*wall;
hole_d = fan_hole * sqrt(open_frac);     // open area = open_frac x blade area

difference() {
    // body: face plate + sleeve
    translate([-outer/2, -outer/2, 0]) cube([outer, outer, face + depth]);
    // sleeve cavity
    translate([-inner/2, -inner/2, face]) cube([inner, inner, depth + 1]);
    // airflow hole
    if (open_frac > 0) translate([0, 0, -1]) cylinder(d = hole_d, h = face + 2);
    // finger notches to pull it off
    for (s = [-1, 1]) translate([s*outer/2, 0, face + depth]) rotate([0, 90, 0])
        cylinder(d = 10, h = 2*wall + 1, center = true);
    // engraved label on the face
    translate([outer/2 - 4, -outer/2 + 4, -0.4]) mirror([1, 0, 0])
        linear_extrude(1) text(str(round(open_frac*100), "%"), size = 5,
                               halign = "left", valign = "bottom");
}
// Material: PETG preferred (PLA is OK at the fan end). Keep every printed part
// at least 5 cm from the lamp. Print face-down, no supports, 0.2 mm layers, 30% infill.
