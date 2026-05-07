function poll_success(singleShot, data){
  // Hide the offline modal
  hideOfflineModal()

  poll_delay = poll_delay_default

  // Schedule the next polling
  if ( !singleShot ){
    setTimeout(function(){doPoll( false ); }, poll_delay);
  }
}

function updateSilenceModeButton(isActive) {
  if (isActive) {
    $('#silenceModeButton').text('Silence Mode: ON').css('background-color', '#c0392b').css('color', '#fff');
  } else {
    $('#silenceModeButton').text('Silence Mode: OFF').css('background-color', '').css('color', '');
  }
}

function initialize_button_handlers(){
  // Fetch initial silence mode state
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
      const chevron_number = $(this).attr('chevron_number');

      $.post({
          url: 'stargate/do/chevron_cycle',
          data: JSON.stringify({
              chevron_number: chevron_number
          })
      })
      .fail(function() {
          console.log("Failed to communicate with Stargate")
          $("<div>Failed to communicate with Stargate</div>").dialog();
      });
  });

  $('.debug_button_container .controlButton').click(function() {
      const action = $(this).attr('action');

      $.post({
          url: 'stargate/do/' + action,
      })
      .fail(function() {
          console.log("Failed to communicate with Stargate")
          $("<div>Failed to communicate with Stargate</div>").dialog();
      });
  });
}
