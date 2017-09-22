function showSuccess( msg )
{
  notif(
    {
      msg:       "<i class='fa fa-check-circle fa-fw'></i> " + msg,
      type:      'success',
      position:  'center',
      width:     400,
      autohide:  true,
      opacity:   1.0,
      fade:      true,
      clickable: true,
      multiline: true,
    }
  );
}

function showWarning( msg )
{
  notif(
    {
      msg:       "<i class='fa fa-exclamation-circle fa-fw'></i> " + msg,
      type:      'warning',
      position:  'center',
      width:     400,
      autohide:  false,
      opacity:   1.0,
      fade:      true,
      multiline: true,
    }
  );
}

function showError( msg )
{
  notif(
    {
      msg:       '<i class="fa fa-exclamation-triangle fa-fw"></i> ' + msg,
      type:      'error',
      position:  'center',
      width:     400,
      autohide:  false,
      opacity:   1.0,
      fade:      true,
      multiline: true,
    }
  );
}

function showInfo( msg )
{
  notif(
    {
      msg:       '<i class="fa fa-info-circle fa-fw"></i> ' + msg,
      type:      'info',
      position:  'center',
      width:     400,
      autohide:  false,
      opacity:   1.0,
      fade:      true,
      multiline: true,
    }
  );
}

function promptForDelete( item, url )
{
  Ply.dialog( 'confirm',
    {
      effect : "3d-flip[180,-180]" // fade, scale, fall, slide, 3d-flip, 3d-sign
    },
    'Are you sure you want to delete "' + item + '"?'
  )
  .always( function(ui)
    {
      if (ui.state)
      {
        window.location.href = url;
        return true;
      }
      else
      {
        return false;
      }
    }
  );
}

function setTimePickers()
{
  jQuery('#start_time1').datetimepicker({
    datepicker:false,
    format:'H:i',
    step: 15
  });
  jQuery('#end_time1').datetimepicker({
    datepicker:false,
    format:'H:i',
    step: 15
  });
  jQuery('#start_time2').datetimepicker({
    datepicker:false,
    format:'H:i',
    step: 15
  });
  jQuery('#end_time2').datetimepicker({
    datepicker:false,
    format:'H:i',
    step: 15
  });
}

function BookmarkToggle( class_id, action )
{
  var bookmark_url = "/bookmark_class/" + class_id + "/" + action;

  $.ajax(
    {
      url: bookmark_url,
      dataType: 'json',
      type: 'GET',
      success: function( data )
      {
        if ( data[0].success < 1 )
        {
            showError( data[0].message );
            return false;
        }
        if ( action == -1 )
        {
          $('#bookmark_' + class_id).html( '<a onClick="BookmarkToggle( '
                                          + class_id
                                          + ', 1 )"><i class="fa fa-bookmark-o fa-fw"></i></a>' );
        }
        else
        {
          $('#bookmark_' + class_id).html( '<a onClick="BookmarkToggle( '
                                          + class_id
                                          + ', -1 )"><i class="fa fa-bookmark fa-fw"></i></a>' );
        }
        showSuccess( data[0].message )
      },
      error: function()
      {
        showError( 'An error occurred, and we could not bookmark this Class. Please try again later.' )
      }
    }
  );
}
