extends Camera2D

var shake_amplitude = 1.5;
var ease_enabled = false;

# Called when the node enters the scene tree for the first time.
func _ready():
	$Shake_Timer.connect("timeout", self, "_shake_timer_ended");
	$Smooth_Timer.connect("timeout", self, "_smooth_timer_ended");

func _process(delta):
	if $Shake_Timer.time_left > 0:
		var ease_factor = 1;
		if ease_enabled:
			ease_factor = clamp(($Shake_Timer.time_left / $Shake_Timer.wait_time), 0.1, 100);
		offset = Vector2(rand_range(0, shake_amplitude / ease_factor), rand_range(0, shake_amplitude / ease_factor))
	if $Smooth_Timer.time_left > 0:
		smoothing_speed = lerp(smooth_lag_start, 10, 1 - $Smooth_Timer.time_left/$Smooth_Timer.wait_time);
# Shakes the camera for the given duration
func shake(duration = 0.1, amplitude = 1.5, ease_enabled = false):
	$Shake_Timer.wait_time = duration;
	shake_amplitude = amplitude;
	self.ease_enabled = ease_enabled;
	$Shake_Timer.start();

var smooth_lag_start;
func lag_smooth(duration = 1, start = 1):
	smoothing_speed = start;
	smooth_lag_start = start;
	$Smooth_Timer.wait_time = duration;
	$Smooth_Timer.start();
	
func _smooth_timer_ended():
	smoothing_speed = 10;

func _shake_timer_ended():
	offset = Vector2(0,0);
	
