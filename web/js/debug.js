// ----------------------------------------------------------------
// Helpers
// ----------------------------------------------------------------

function hexToRgb(hex) {
  var r = parseInt(hex.slice(1, 3), 16);
  var g = parseInt(hex.slice(3, 5), 16);
  var b = parseInt(hex.slice(5, 7), 16);
  return [r, g, b];
}

function rgbToHex(r, g, b) {
  return '#' + [r, g, b].map(function(v) {
    return ('0' + Math.max(0, Math.min(255, v)).toString(16)).slice(-2);
  }).join('');
}

// ----------------------------------------------------------------
// Polling / gate-offline hook
// ----------------------------------------------------------------

function poll_success(singleShot, data) {
  hideOfflineModal();
  poll_delay = poll_delay_default;
  updateLampStatus(data);
  if (!singleShot) {
    setTimeout(function() { doPoll(false); }, poll_delay);
  }
}

// ----------------------------------------------------------------
// Silence mode
// ----------------------------------------------------------------

function updateSilenceModeButton(isActive) {
  if (isActive) {
    $('#silenceModeButton').text('Silence Mode: ON').css('background-color', '#c0392b').css('color', '#fff');
  } else {
    $('#silenceModeButton').text('Silence Mode: OFF').css('background-color', '').css('color', '');
  }
}

// ----------------------------------------------------------------
// General button handlers (existing)
// ----------------------------------------------------------------

function initialize_button_handlers() {
  $.get('stargate/get/dialing_status')
    .done(function(data) {
      updateSilenceModeButton(data.silence_mode);
    });

  $('#silenceModeButton').click(function() {
    $.post('stargate/do/toggle_silence_mode')
      .done(function(data) {
        updateSilenceModeButton(data.silence_mode);
      })
      .fail(function() {
        console.log("Failed to communicate with Stargate");
      });
  });

  $('.debug_button_container .cycleChevronButton').click(function() {
    var chevron_number = $(this).attr('chevron_number');
    $.post({
      url: 'stargate/do/chevron_cycle',
      data: JSON.stringify({ chevron_number: chevron_number })
    }).fail(function() {
      console.log("Failed to communicate with Stargate");
      $("<div>Failed to communicate with Stargate</div>").dialog();
    });
  });

  $('.debug_button_container .controlButton').click(function() {
    var action = $(this).attr('action');
    if (!action) return;
    $.post({ url: 'stargate/do/' + action })
      .fail(function() {
        console.log("Failed to communicate with Stargate");
        $("<div>Failed to communicate with Stargate</div>").dialog();
      });
  });
}

// ----------------------------------------------------------------
// Lamp Mode controls
// ----------------------------------------------------------------

var _lampAnimations = [];   // [{id, name}, ...]
var _activeAnimationId = 'static';

function updateLampStatus(data) {
  if (data === undefined || data.lamp_mode === undefined) return;

  var isOn = data.lamp_mode;
  var color = data.lamp_color || [255, 255, 255];
  var brightness = data.lamp_brightness !== undefined ? data.lamp_brightness : 255;
  var animId = data.lamp_animation || 'static';

  // State label
  $('#lamp_state_label')
    .text(isOn ? 'ON' : 'OFF')
    .css('color', isOn ? '#27ae60' : '#c0392b');

  // Color swatch + label
  var hex = rgbToHex(color[0], color[1], color[2]);
  $('#lamp_color_swatch').css('background-color', hex);
  $('#lamp_color_label').text(hex + ' (' + color.join(', ') + ')');

  // Brightness
  $('#lamp_brightness_label').text(brightness);

  // Animation name
  var animName = animId;
  $.each(_lampAnimations, function(_, a) {
    if (a.id === animId) { animName = a.name; return false; }
  });
  $('#lamp_animation_label').text(animName);

  // Sync controls to current values (only when not actively dragging)
  if (!$('#lamp_color_picker').is(':focus')) {
    $('#lamp_color_picker').val(hex);
  }
  if (!$('#lamp_brightness_slider').is(':active')) {
    $('#lamp_brightness_slider').val(brightness);
    $('#lamp_brightness_value').text(brightness);
  }

  // Highlight active animation button
  _activeAnimationId = animId;
  refreshAnimationButtonStyles();
}

function refreshAnimationButtonStyles() {
  $('#lamp_animation_buttons button').each(function() {
    var id = $(this).data('anim-id');
    if (id === _activeAnimationId) {
      $(this).css({ 'background-color': '#2980b9', 'color': '#fff', 'border-color': '#1a5276' });
    } else {
      $(this).css({ 'background-color': '#e0e0e0', 'color': '#000', 'border-color': '#aaa' });
    }
  });
}

function buildAnimationButtons(animations) {
  var $container = $('#lamp_animation_buttons');
  $container.empty();
  $.each(animations, function(_, anim) {
    var $btn = $('<button type="button"></button>')
      .text(anim.name)
      .data('anim-id', anim.id)
      .css({
        'padding': '6px 16px',
        'border': '2px solid #aaa',
        'border-radius': '4px',
        'cursor': 'pointer',
        'font-size': '0.95em',
        'height': '40px',
        'background-color': '#e0e0e0',
        'color': '#000'
      })
      .click(function() {
        _activeAnimationId = anim.id;
        refreshAnimationButtonStyles();
        sendLampSet({ animation: anim.id });
      });
    $container.append($btn);
  });
  refreshAnimationButtonStyles();
}

function sendLampOn(extraPayload) {
  var hex = $('#lamp_color_picker').val();
  var rgb = hexToRgb(hex);
  var brightness = parseInt($('#lamp_brightness_slider').val(), 10);
  var payload = { color: rgb, brightness: brightness, animation: _activeAnimationId };
  if (extraPayload) $.extend(payload, extraPayload);

  $.ajax({
    url: 'stargate/do/lamp_on',
    type: 'POST',
    contentType: 'application/json',
    data: JSON.stringify(payload)
  }).done(function(data) {
    updateLampStatus(data);
  }).fail(function() {
    console.log("lamp_on failed");
  });
}

function sendLampOff() {
  $.ajax({
    url: 'stargate/do/lamp_off',
    type: 'POST',
    contentType: 'application/json',
    data: JSON.stringify({})
  }).done(function(data) {
    updateLampStatus($.extend({ lamp_mode: false }, data));
    // Refresh full status so animation label updates
    $.get('stargate/get/dialing_status').done(function(d) { updateLampStatus(d); });
  }).fail(function() {
    console.log("lamp_off failed");
  });
}

function sendLampSet(extraPayload) {
  var hex = $('#lamp_color_picker').val();
  var rgb = hexToRgb(hex);
  var brightness = parseInt($('#lamp_brightness_slider').val(), 10);
  var payload = { color: rgb, brightness: brightness };
  if (extraPayload) $.extend(payload, extraPayload);

  $.ajax({
    url: 'stargate/do/lamp_set',
    type: 'POST',
    contentType: 'application/json',
    data: JSON.stringify(payload)
  }).done(function(data) {
    if (data.success === false) {
      // lamp was off — turn it on instead
      sendLampOn(extraPayload);
    } else {
      // refresh full status
      $.get('stargate/get/dialing_status').done(function(d) { updateLampStatus(d); });
    }
  }).fail(function() {
    console.log("lamp_set failed");
  });
}

function initLampControls() {
  // Fetch animations list
  $.get('stargate/get/lamp_animations').done(function(data) {
    _lampAnimations = data.animations || [];
    buildAnimationButtons(_lampAnimations);
  });

  // Fetch current lamp state
  $.get('stargate/get/dialing_status').done(function(data) {
    updateLampStatus(data);
  });

  // Brightness slider — live preview label
  $('#lamp_brightness_slider').on('input', function() {
    $('#lamp_brightness_value').text($(this).val());
  });

  // ON button
  $('#lamp_on_btn').click(function() {
    sendLampOn();
  });

  // OFF button
  $('#lamp_off_btn').click(function() {
    sendLampOff();
  });

  // Apply button — sends color + brightness (keeps current animation)
  $('#lamp_apply_btn').click(function() {
    sendLampSet();
  });
}
