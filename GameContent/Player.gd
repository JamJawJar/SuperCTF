extends KinematicBody2D

var control = false;
var IS_CONTROLLED_BY_MOUSE = false;
# The ID of this player 0,1,2 etc. NOT the network unique ID
var player_id = -1;
var team_id = -1;
var BASE_SPEED = 200;
const AIMING_SPEED = 15;
const SPRINT_SPEED = 50;
var TELEPORT_SPEED = 2000;
var player_name = "Guest999";
var speed = BASE_SPEED;
# Where this player starts on the map and should respawn at
var start_pos = Vector2(0,0);
# Whether or not this player is alive
var alive = true;
# Whether or not this player is currently invincible
var invincible = false;
# The camera that is associated with this player. A reference is used because it may switch parents
var camera_ref = null;
# The direction the laser is firing at
var laser_direction = Vector2(0,0);
# The position the laser is firing from
var laser_position = Vector2(0,0);
# The number of bullets this player has shot. Used for naming bullets
var bullets_shot = 0;
# The time in millis the last position was received
var time_of_last_received_pos = 0;
# The position to start lerping from
var lerp_start_pos = Vector2(0,0);
# The position to end lerping at
var lerp_end_pos = Vector2(0,0);
# Whether or not the player is sprinting
var sprintEnabled = false;
var max_forcefield_distance = 5000;
var remote_db_level = -10;
# The position the player was in last frame
var last_position = Vector2(0,0);


var bullet_atlas_blue = preload("res://Assets/Weapons/bullet_b.png");
var bullet_atlas_red = preload("res://Assets/Weapons/bullet_r.png");

var running_top_atlas_blue = preload("res://Assets/Player/running_top_B.png");
var running_top_atlas_red = preload("res://Assets/Player/running_top_R.png");

var shooting_top_atlas_blue = preload("res://Assets/Player/shooting_top_B.png");
var shooting_top_atlas_red = preload("res://Assets/Player/shooting_top_R.png");

var idle_top_atlas_blue = preload("res://Assets/Player/idle_top_B.png");
var idle_top_atlas_red = preload("res://Assets/Player/idle_top_R.png");

func _ready():
	camera_ref = $Center_Pivot/Camera;
	
	last_position = position;
	
	if Globals.testing:
		activate_camera();
		control = true
	
	if Globals.testing or Globals.localPlayerID == player_id:
		$Laser_Timer.wait_time += 0.1;
		$Laser_Charge_Audio.set_pitch_scale(float(0.5)/$Laser_Timer.wait_time);
		if !Globals.testing:
			Globals.result_player_team_id = team_id;
	else:
		$Laser_Charge_Audio.set_volume_db(remote_db_level);
		$Laser_Fire_Audio.set_volume_db(remote_db_level);
	
	$Respawn_Timer.connect("timeout", self, "_respawn_timer_ended");
	$Invincibility_Timer.connect("timeout", self, "_invincibility_timer_ended");
	$Laser_Timer.connect("timeout", self, "_laser_timer_ended");
	$Laser_Input_Timer.connect("timeout", self, "_laser_input_timer_ended");
	#$Laser_Cooldown_Timer.connect("timeout", self, "_laser_cooldown_timer_ended");
	$Forcefield_Timer.connect("timeout", self, "_forcefield_timer_ended");
	$Animation_Timer.connect("timeout", self, "_animation_timer_ended");
	$Shoot_Animation_Timer.connect("timeout", self, "_shoot_animation_timer_ended");
	$Shoot_Animation_Timer.wait_time = $Animation_Timer.wait_time * $Sprite_Top.vframes;
	lerp_start_pos = position;
	lerp_end_pos = position;

func _input(event):
	if Globals.is_typing_in_chat:
		return;
	if control:
		if event is InputEventKey and event.pressed:
			if event.scancode == KEY_T:
				get_tree().get_root().get_node("MainScene/NetworkController").rpc("test_ping");
			if event.scancode == KEY_CONTROL:
				if $Flag_Holder.get_child_count() == 0:
					sprintEnabled = !sprintEnabled;
			if event.scancode == KEY_SHIFT:
				switch_weapons();
			if event.scancode == KEY_SPACE:
				#Attempt a teleport
				# Re-enable line below to prevent telporting while you have flag
				# if $Flag_Holder.get_child_count() == 0:
				if $Teleport_Timer.time_left == 0:
					move_on_inputs(true);
					camera_ref.lag_smooth();
					$Teleport_Timer.start();
			if event.scancode == KEY_E:
				# If were not holding a flag, create forcefield
				if $Flag_Holder.get_child_count() == 0:
					if $Forcefield_Timer.time_left == 0:
						forcefield_placed();
		elif IS_CONTROLLED_BY_MOUSE and event is InputEventMouseButton:
			if event.button_index == BUTTON_LEFT:
				if event.pressed: # Click down
					# Only accepts clicks if we're not aiming a laser
					if $Laser_Timer.time_left == 0:
						if $Flag_Holder.get_child_count() == 0:
							if $Shoot_Cooldown_Timer.time_left == 0:
								shoot_bullet((get_global_mouse_position() - global_position).normalized());
							sprintEnabled = false;
						else: # Otherwise drop our flag
							drop_current_flag($Flag_Holder.get_global_position());
							rpc_id(1, "send_drop_flag", $Flag_Holder.get_global_position());
				else: # Click up
					pass
			if event.button_index == BUTTON_RIGHT:
				if event.pressed:
					# Only accepts clicks if we're not aiming a laser
					if $Laser_Timer.time_left == 0:
						if $Flag_Holder.get_child_count() == 0:
							var direction = (get_global_mouse_position() - global_position).normalized();
							rpc_id(1, "send_start_laser", direction, position, $Sprite_Top.frame);
							start_laser(direction, position, $Sprite_Top.frame);
							sprintEnabled = false;
						else: # Otherwise drop our flag
							drop_current_flag($Flag_Holder.get_global_position());
							rpc_id(1, "send_drop_flag", $Flag_Holder.get_global_position());
				else:
					pass;

func _process(delta):
	var new_speed = get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("playerSpeed");
	if speed == BASE_SPEED:
		speed = new_speed;
	BASE_SPEED = new_speed;
	TELEPORT_SPEED = get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("dashDistance");
	$Shoot_Cooldown_Timer.wait_time = float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("bulletCooldown"))/1000.0;
	$Laser_Cooldown_Timer.wait_time = float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("laserCooldown"))/1000.0;
	$Forcefield_Timer.wait_time = float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("forcefieldCooldown"))/1000.0;
	$Teleport_Timer.wait_time = float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("dashCooldown"))/1000.0;
	$Laser_Timer.wait_time = float(get_tree().get_root().get_node("MainScene/NetworkController").get_game_var("laserChargeTime"))/1000.0;
	if control:
		activate_camera();
		# Don't look around if we're shooting a laser
		if $Laser_Timer.time_left == 0:
			update_look_direction();
		if $Laser_Timer.time_left + $Laser_Input_Timer.time_left > 0:
			speed = AIMING_SPEED * ($Laser_Timer.time_left / $Laser_Timer.wait_time);
		# Move & Shoot around as long as we aren't typing in chat
		if !Globals.is_typing_in_chat:
			move_on_inputs();
			if !IS_CONTROLLED_BY_MOUSE:
				shoot_on_inputs();
	update();
	if $Invincibility_Timer.time_left > 0:
		var t = $Invincibility_Timer.time_left / $Invincibility_Timer.wait_time 
		var x =  (t * 10);
		$Sprite_Top.modulate = Color(1,1,1,(sin( (PI / 2) + (x * (1 + (t * ((2 * PI) - 1))))) + 1)/2)
		$Sprite_Bottom.modulate = Color(1,1,1,(sin( (PI / 2) + (x * (1 + (t * ((2 * PI) - 1))))) + 1)/2)
	z_index = global_position.y + 15;
	
	
	
	# If we are a puppet and not the server, then lerp our position
	if !Globals.testing and !is_network_master() and !get_tree().is_network_server():
		position = lerp(lerp_start_pos, lerp_end_pos, clamp(float(OS.get_ticks_msec() - time_of_last_received_pos)/float(Globals.player_lerp_time), 0.0, 1.0));
	
	if !Globals.testing and is_network_master() and !get_tree().is_network_server():
		rpc_unreliable_id(1, "send_position", position, player_id);
	
	
	# Idle Animation
	var diff = last_position - position;
	if sqrt(pow(diff.x, 2) + pow(diff.y, 2)) < 1:
		if team_id == 1:
			$Sprite_Top.set_texture(idle_top_atlas_red);
		else:
			$Sprite_Top.set_texture(idle_top_atlas_blue);
		$Sprite_Bottom.frame = $Sprite_Top.frame % $Sprite_Top.hframes;
	else:
		if team_id == 1:
			$Sprite_Top.set_texture(running_top_atlas_red);
		else:
			$Sprite_Top.set_texture(running_top_atlas_blue);
		$Sprite_Bottom.frame = $Sprite_Top.frame;
		
	# Shooting Animation (Overrides idleness)
	if $Shoot_Animation_Timer.time_left > 0:
		if team_id == 1:
			$Sprite_Top.set_texture(shooting_top_atlas_red);
		else:
			$Sprite_Top.set_texture(shooting_top_atlas_blue);
		
	# Name tag
	var color = "blue";
	if team_id == 1:
		color = "red";
	$Label_Name.bbcode_text = "[center][color=" + color + "]" + player_name;
	last_position = position;
	
remote func send_start_laser(direction, player_pos, frame):
	if get_tree().is_network_server():# Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_start_laser", direction, player_pos, frame);
		start_laser(direction, player_pos, frame); # Also call it locally for the server

remote func receive_start_laser(direction, player_pos, frame):
	start_laser(direction, player_pos, frame);

func start_laser(direction, start_pos, frame):
	$Sprite_Top.frame = frame;
	$Sprite_Bottom.frame = frame;
	laser_direction = direction;
	laser_position = start_pos;
	$Laser_Timer.start();
	speed = AIMING_SPEED;
	camera_ref.shake($Laser_Timer.wait_time, 1, true);
	$Laser_Charge_Audio.play();

func _laser_timer_ended():
	shoot_laser();
	speed = BASE_SPEED;

func start_laser_input():
	$Laser_Input_Timer.start();
func _laser_input_timer_ended():
	var start_pos = get_node("Bullet_Starts/" + String($Sprite_Top.frame % $Sprite_Top.hframes)).position;
	rpc_id(1, "send_start_laser", laser_direction, start_pos, $Sprite_Top.frame);
	start_laser(laser_direction, start_pos, $Sprite_Top.frame);
	sprintEnabled = false;
	
var current_weapon = 0;
func switch_weapons():
	current_weapon = 1 if current_weapon == 0 else 0;

# Called when the player attempts to place a forcefield
# This function will either place it in the appropriate spot or deny it (bad location or something)
func forcefield_placed():
	var forcefield_position;
	if IS_CONTROLLED_BY_MOUSE:
		var distance = get_global_mouse_position().distance_to(position);
		forcefield_position = get_global_mouse_position();
		if distance > max_forcefield_distance:
			var direction = (get_global_mouse_position() - global_position).normalized();
			forcefield_position = global_position + (direction * max_forcefield_distance);
	else:
		forcefield_position = position;
	rpc("spawn_forcefield", forcefield_position, team_id);
	$Forcefield_Timer.start();
	if Globals.testing:
		var forcefield = load("res://GameContent/Forcefield.tscn").instance();
		forcefield.position = forcefield_position;
		forcefield.team_id = team_id;
		get_tree().get_root().get_node("MainScene").add_child(forcefield);
		
# Called when the forcefield cooldown timer ends
func _forcefield_timer_ended():
	pass;

# Called by client telling everyone to spawn a forcefield in a spot
# TODO - in future this should be handled by servers - not the client.
remotesync func spawn_forcefield(pos, team_id):
	var forcefield = load("res://GameContent/Forcefield.tscn").instance();
	forcefield.position = pos;
	forcefield.player_id = player_id;
	forcefield.team_id = team_id;
	get_tree().get_root().get_node("MainScene").add_child(forcefield);


# Shoots a laser shot
func shoot_laser():
	if is_network_master():
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE);
	# Only run if we're the server
	var laser = load("res://GameContent/Laser.tscn").instance();
	get_tree().get_root().get_node("MainScene").add_child(laser);
	laser.position = position + laser_position;
	laser.rotation = Vector2(0,0).angle_to_point(laser_direction) + PI/2;
	laser.player_id = player_id;
	laser.team_id = team_id;
	$Laser_Fire_Audio.play();
	$Laser_Cooldown_Timer.start();


func _draw():
	if $Laser_Timer.time_left > 0:
		var size;
		if $Laser_Input_Timer.time_left > 0:
			size = 0;
		else:
			size = clamp(1 / ($Laser_Timer.time_left / $Laser_Timer.wait_time), 0 , 5);
		var red = 1 if team_id == 1 else 0;
		var green = 10.0/255.0 if team_id == 1 else 130.0/255.0;
		var blue = 1 if team_id == 0 else 0;
		var lightener = 0.2;
		red = red + lightener;
		green = green + lightener;
		blue = blue + lightener;
		draw_line(laser_position, laser_direction * 1000, Color(red, green, blue, 1 - ($Laser_Timer.time_left / $Laser_Timer.wait_time)), size);


# Shoots a bullet shot
func shoot_bullet(d):
	$Shoot_Cooldown_Timer.start();
	var direction = d.normalized();
	bullets_shot = bullets_shot + 1;
	# Re-enable the code below to have the bullet start out of the end of the gun
	var bullet_start = position + get_node("Bullet_Starts/" + String($Sprite_Top.frame % $Sprite_Top.hframes)).position;
	# Offset bullet start by a bit because player frames are perfectly centered
	if false and direction.y == 0:
		bullet_start += Vector2(0, 10);
	if false and direction.x != 0 and direction.y != 0:
		bullet_start += Vector2(10 * direction.x/abs(direction.x),0);
	var time = OS.get_system_time_msecs() - Globals.match_start_time;
	var bullet = spawn_bullet(bullet_start, 0 if Globals.testing else player_id, direction,time, null);
	#camera_ref.shake();
	$Shoot_Animation_Timer.start();
	animation_set_frame = 0;
	if !Globals.testing:
		rpc_id(1, "send_bullet", bullet_start,player_id, direction, time, bullet.name);

# Spawns a bullet given various initializaiton parameters
func spawn_bullet(pos, player_id, direction, time_shot, bullet_name = null):
	
	# Muzzle Flair
	var particles = load("res://GameContent/Muzzle_Bullet.tscn").instance();
	particles.team_id = team_id;
	#get_tree().get_root().get_node("MainScene").add_child(particles);
	call_deferred("add_child", particles);
	particles.position = get_node("Bullet_Starts/" + String($Sprite_Top.frame % $Sprite_Top.hframes)).position;
	particles.rotation = Vector2(0,0).angle_to_point(direction) + PI;
	
#	# If this was fired by another player, compensate for player lerp speed
	if !Globals.testing and player_id != Globals.localPlayerID:
		var t = Timer.new()
		t.set_wait_time(float(Globals.player_lerp_time)/float(1000.0))
		t.set_one_shot(true)
		self.add_child(t)
		t.start()
		yield(t, "timeout")
		t.queue_free();
		print("waited");
	
	# Initialize Bullet
	var bullet = load("res://GameContent/Bullet.tscn").instance();
	bullet.position = pos;
	bullet.direction = direction;
	bullet.player_id = player_id;
	bullet.team_id = team_id;
	bullet.initial_time_shot = time_shot
	bullet.set_network_master(get_network_master());
	if team_id == 0:
		bullet.get_node("Sprite").set_texture(bullet_atlas_blue);
	elif team_id == 1:
		bullet.get_node("Sprite").set_texture(bullet_atlas_red);
	get_tree().get_root().get_node("MainScene").call_deferred("add_child", bullet);
	if bullet_name != null:
		bullet.name = bullet_name;
	else:
		bullet.name = bullet.name + "-" + str(player_id) + "-" + str(bullets_shot);
	
	
	return bullet;

# A vector 2D representing the last movement key directions pressed
var last_movement_input = Vector2(0,0);

# Checks the current pressed keys and calculates a new player position using the KinematicBody2D
func move_on_inputs(teleport = false):
	var input = Vector2(0,0);
	input.x = (1 if Input.is_key_pressed(KEY_D) else 0) - (1 if Input.is_key_pressed(KEY_A) else 0)
	input.y = (1 if Input.is_key_pressed(KEY_S) else 0) - (1 if Input.is_key_pressed(KEY_W) else 0)
	input = input.normalized();
	last_movement_input = input;
	
	
	var move_speed = speed;
	if sprintEnabled:
		move_speed += SPRINT_SPEED;
	if teleport:
		move_speed = TELEPORT_SPEED;
	var vec = (input * move_speed);
	
	var previous_pos = position;
	var change = move_and_slide(vec);
	var new_pos = position;
	
	if teleport:
		if Globals.testing:
			$Teleport_Audio.play();
		else:
			rpc("create_ghost_trail", previous_pos, new_pos);

func shoot_on_inputs():
	var input = Vector2(0,0);
	input.x = (1 if Input.is_key_pressed(KEY_RIGHT) else 0) - (1 if Input.is_key_pressed(KEY_LEFT) else 0)
	input.y = (1 if Input.is_key_pressed(KEY_DOWN) else 0) - (1 if Input.is_key_pressed(KEY_UP) else 0)
	input = input.normalized();
	if input != Vector2.ZERO:
		if $Flag_Holder.get_child_count() != 0:
			drop_current_flag($Flag_Holder.get_global_position());
			if !Globals.testing:
				rpc_id(1, "send_drop_flag", $Flag_Holder.get_global_position());
		elif current_weapon == 0 and $Shoot_Cooldown_Timer.time_left == 0:
			shoot_bullet(input);
		elif current_weapon == 1 and $Laser_Cooldown_Timer.time_left == 0:
			# If we are still in input phase, update direction
			if $Laser_Input_Timer.time_left != 0:
				laser_direction = input;
				laser_position = get_node("Bullet_Starts/" + String($Sprite_Top.frame % $Sprite_Top.hframes)).position;
			elif $Laser_Timer.time_left == 0:
				start_laser_input();

remotesync func create_ghost_trail(start, end):
	$Teleport_Audio.play();
	for i in range(6):
		var node = load("res://GameContent/Ghost_Trail.tscn").instance();
		get_tree().get_root().get_node("MainScene").add_child(node);
		node.position = start;
		node.position.x = node.position.x + ((i) * (end.x - start.x)/4)
		node.position.y = node.position.y + ((i) * (end.y - start.y)/4)
		node.get_node("Death_Timer").start((i) * 0.05 + 0.0001);
		node.get_node("Sprite_Top").texture = $Sprite_Top.texture
		node.get_node("Sprite_Top").hframes = $Sprite_Top.hframes
		node.get_node("Sprite_Top").vframes = $Sprite_Top.vframes
		node.get_node("Sprite_Top").frame = $Sprite_Top.frame
		node.get_node("Sprite_Top").scale = $Sprite_Top.scale
		node.get_node("Sprite_Bottom").texture = $Sprite_Bottom.texture
		node.get_node("Sprite_Bottom").hframes = $Sprite_Bottom.hframes
		node.get_node("Sprite_Bottom").vframes = $Sprite_Bottom.vframes
		node.get_node("Sprite_Bottom").frame = $Sprite_Bottom.frame
		node.get_node("Sprite_Bottom").scale = $Sprite_Bottom.scale
	# If this is a puppet, use this ghost trail as an oppurtunity to also update its position
	if !is_network_master():
		lerp_start_pos = end;
		lerp_end_pos = end;
		position = end;
	
# Changes the sprite's frame to make it "look" at the mouse
var previous_look_input = Vector2(0,0);
func update_look_direction():
	var pos;
	if IS_CONTROLLED_BY_MOUSE:
		pos = get_global_mouse_position();
	else:
		var input = Vector2(0,0);
		input.x = (1 if Input.is_key_pressed(KEY_RIGHT) else 0) - (1 if Input.is_key_pressed(KEY_LEFT) else 0)
		input.y = (1 if Input.is_key_pressed(KEY_DOWN) else 0) - (1 if Input.is_key_pressed(KEY_UP) else 0)
		input = input.normalized();
		if input == Vector2(0,0):
			input.x = (1 if Input.is_key_pressed(KEY_D) else 0) - (1 if Input.is_key_pressed(KEY_A) else 0)
			input.y = (1 if Input.is_key_pressed(KEY_S) else 0) - (1 if Input.is_key_pressed(KEY_W) else 0)
			input = input.normalized();
			if input == Vector2(0,0):
				input = previous_look_input;
		previous_look_input = input;
		pos = position + (input * 100) + Vector2(1,1); # Add 1,1 to prevent 0 edge cases
	var dist = pos - position;
	var angle = get_vector_angle(dist);
	var adjustedAngle = -1 * (angle + (PI/8));
	var octant = (adjustedAngle / (2 * PI)) * 8
	var frame = int((octant + 9) + 4) % 8;
	frame += animation_set_frame * $Sprite_Top.hframes;
	if frame != $Sprite_Top.frame: # If it changed since last time
		set_look_direction(frame);
		if !Globals.testing:
			rpc_unreliable_id(1, "send_look_direction", frame, player_id);
var animation_set_frame = 0;
# Called when the animation timer fires
func _animation_timer_ended():
	animation_set_frame += 1;
	animation_set_frame = animation_set_frame % $Sprite_Top.vframes;

func _shoot_animation_timer_ended():
	if team_id == 1:
		$Sprite_Top.set_texture(running_top_atlas_red);
	else:
		$Sprite_Top.set_texture(running_top_atlas_blue);

# Gets the angle that a vector is making
func get_vector_angle(dist):
	var angle = (-(PI / 2) if dist.y < 0 else ( 3 * PI / 2)) if dist.x == 0 else atan(dist.y / dist.x);
	angle = angle * -1;
	angle += PI/2;
	if dist.x < 0:
		angle += PI;
	return angle;

# Set the direction that the player is "looking" at by changing sprite frame
func set_look_direction(frame):
	$Sprite_Top.frame = frame;
	$Sprite_Bottom.frame = frame;
	

# Updates this player's position with the new given position. Only ever called remotely
func update_position(new_pos):
	# Instantly update position for server
	if get_tree().is_network_server():
		position = new_pos;
		return;
	# Otherwise lerp
	
	position = lerp(lerp_start_pos, lerp_end_pos, clamp(float(OS.get_ticks_msec() - time_of_last_received_pos)/float(Globals.player_lerp_time), 0.0, 1.0));
	time_of_last_received_pos = OS.get_ticks_msec();
	lerp_start_pos = position;
	lerp_end_pos = new_pos;

# Activates the camera on this player
func activate_camera():
	if camera_ref:
		camera_ref.current = true;

# De-activates the camera on this player
func deactivate_camera():
	if camera_ref:
		camera_ref.current = false;

# Called when this player is hit by a projectile
func hit_by_projectile(attacker_id, projectile_type):
	if projectile_type == 0 || projectile_type == 1: # Bullet or Laser
		die();
		var attacker_team_id = get_tree().get_root().get_node("MainScene/NetworkController").players[attacker_id]["team_id"]
		var attacker_name = get_tree().get_root().get_node("MainScene/NetworkController").players[attacker_id]["name"]
		if attacker_id == Globals.localPlayerID:
			var color = "blue"
			if team_id == 1:
				color = "red";
			get_tree().get_root().get_node("MainScene/UI_Layer").set_alert_text("[center][color=black]KILLED [color=" + color +"]" + player_name);
		if is_network_master():
			get_tree().get_root().get_node("MainScene/UI_Layer").set_big_label_text("KILLED BY\n" + str(attacker_name), attacker_team_id);
			camera_ref.get_parent().remove_child(camera_ref);
			get_tree().get_root().get_node("MainScene/Players/P" + str(attacker_id) + "/Center_Pivot").add_child(camera_ref);
		

# "Kills" the player. Only for visuals on client - the server handles the respawning.
func die():
	visible = false;
	control = false;
	alive = false;
	spawn_death_particles();
	# If we're the server
	if get_tree().is_network_server():
		$Respawn_Timer.start();
	# Drop the flag if you have one
	drop_current_flag($Flag_Holder.get_global_position());
	position = start_pos;
	if is_network_master():
		$Death_Audio.play();
	else:
		$Killed_Audio.play();

func spawn_death_particles():
	var node = load("res://GameContent/Player_Death.tscn").instance();
	node.position = position;
	node.xFrame = $Sprite_Top.frame_coords.x;
	node.z_index = z_index;
	get_tree().get_root().get_node("MainScene").add_child(node);

# Called by the respawn timer when it ends
func _respawn_timer_ended():
	rpc("receive_respawn");

# Respawns the player at their team's start location
func respawn():
	visible = true;
	alive = true;
	position = start_pos;
	if is_network_master():
		control = true;
	start_temporary_invincibility();
	if is_network_master():
		get_tree().get_root().get_node("MainScene/UI_Layer").clear_big_label_text();
		camera_ref.get_parent().remove_child(camera_ref);
		$Center_Pivot.add_child(camera_ref);
	else:
		lerp_start_pos = position;
		lerp_end_pos = position;
		time_of_last_received_pos = 0;

# Takes the given flag
func take_flag(flag_id):
	if Globals.testing or is_network_master():
		get_tree().get_root().get_node("MainScene").speedup_music();
	$Flag_Pickup_Audio.play();
	var flag_team_id;
	for flag in get_tree().get_nodes_in_group("Flags"):
		if flag.flag_id == flag_id:
			flag.re_parent($Flag_Holder);
			flag.is_at_home = false;
			flag.position = Vector2(0,0);
			flag_team_id = flag.team_id;
	sprintEnabled = false;
	var subject = player_name;
	var subjectColor = "blue"
	var color = "red";
	var teamNoun = "RED TEAM";
	if team_id == 1:
		subjectColor = "red";
		color = "blue";
		teamNoun = "BLUE TEAM";
	if player_id == Globals.localPlayerID:
		subject = "You";
	if !get_tree().is_network_server():
		if get_tree().get_root().get_node("MainScene/NetworkController").players[Globals.localPlayerID]["team_id"] == flag_team_id:
			teamNoun = "YOUR TEAM";
		get_tree().get_root().get_node("MainScene/UI_Layer").set_alert_text("[center][color=" + subjectColor + "]" + subject + "[color=black] took " + "[color=" + color + "]" + teamNoun + "'s[color=black] flag!");
	

# Drops the currently held flag (If there is one)
func drop_current_flag(flag_position = $Flag_Holder.get_global_position()):
	# Only run if there is a flag in the Flag_Holder
	if $Flag_Holder.get_child_count() > 0:
		if Globals.testing or is_network_master():
			get_tree().get_root().get_node("MainScene").slowdown_music();
		$Flag_Drop_Audio.play();
		# Just get the first flag because there should only ever be one
		var flag = $Flag_Holder.get_children()[0];
		flag.get_node("Area2D").player_id_drop_buffer = player_id;
		flag.get_node("Area2D").ignore_next_buffer_reset = true;
		flag.re_parent(get_tree().get_root().get_node("MainScene"));
		flag.position = flag_position;
		$Shoot_Cooldown_Timer.start();
		$Laser_Cooldown_Timer.start();

# Starts the temporary Invincibility cooldown
func start_temporary_invincibility():
	$Invincibility_Timer.start();
	invincible = true;
# Called by timer when invincibility is over
func _invincibility_timer_ended():
	# If we're the server, make the call to actually end invinciblity
	if get_tree().is_network_server():
		rpc("receive_end_invinciblity");



# -------- NETWORKING ------------------------------------------------------------>



# Client tells Server to run this function so that it can send it's latest position
# The Server then sends that position to all other clients
remote func send_position(new_pos, player_id):
	if get_tree().is_network_server(): # Only run if it's the server
		get_tree().get_root().get_node("MainScene/NetworkController").players[player_id]["position"] = position;
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_unreliable_id(i, "receive_position", new_pos);
		update_position(new_pos); # Also call it locally for the server

# "Receives" the position of this player from the server
remote func receive_position(new_pos):
	update_position(new_pos);

# Client tells the server that it just shot a bullet
remote func send_bullet(pos, player_id, direction, time_shot, bullet_name):
	if get_tree().is_network_server(): # Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_bullet", pos, player_id, direction,time_shot, bullet_name);
		spawn_bullet(pos, player_id, direction,time_shot, bullet_name); # Also call it locally for the server

# "Receives" a bullet from the server that was shot by another client
remote func receive_bullet(pos, player_id, direction,time_shot, bullet_name):
	spawn_bullet(pos, player_id, direction,time_shot, bullet_name);

# Client tells the server what direction frame it's looking at 
remote func send_look_direction(frame, player_id):
	if get_tree().is_network_server(): # Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_look_direction", frame);
		set_look_direction(frame); # Also call it locally for the server

# "Receives" the direction frame that this player is looking at from the server
remote func receive_look_direction(frame):
	set_look_direction(frame);

# "Receives" notification from the server that this player was hit by a projectile
remotesync func receive_hit(attacker_id, projectile_type):
	hit_by_projectile(attacker_id, projectile_type);

# Receives notification from the server that this player took the given flag
remotesync func receive_take_flag(flag_id):
	take_flag(flag_id);

# Client tells server that it is dropping the flag
remote func send_drop_flag(flag_position):
	if get_tree().is_network_server():# Only run if it's the server
		var clients = get_tree().get_network_connected_peers();
		for i in clients: # For each connected client
			if i != get_tree().get_rpc_sender_id(): # Don't do it for the player who sent it
				rpc_id(i, "receive_drop_flag", flag_position);
		drop_current_flag(flag_position); # Also call it locally for the server

# Sent by server to tell clients that this player dropped its flag at the given position
remote func receive_drop_flag(flag_position):
	drop_current_flag(flag_position);

# Receives notification from the server to respawn this player
remotesync func receive_respawn():
	respawn();

# Received by server to end this player's invincibility
remotesync func receive_end_invinciblity():
	invincible = false;
	$Invincibility_Timer.stop();
	$Sprite_Top.modulate = Color(1,1,1,1);
	$Sprite_Bottom.modulate = Color(1,1,1,1);
