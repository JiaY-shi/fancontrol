'use strict';
'require view';
'require fs';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function () {
		var m, s, o, v;

		m = new form.Map('fancontrol', _('Fan General Control'));
		s = m.section(form.TypedSection, 'fancontrol', _('Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'), _('Enabled'));
		o.rmempty = false;

		o = s.option(form.Value, 'thermal_file', _('Thermal File'), _('Thermal File'));
		o.placeholder = '/sys/devices/virtual/thermal/thermal_zone0/temp';

		o = s.option(form.Value, 'fan_file', _('Fan File'), _('Fan Speed File'));
		o.placeholder = '/sys/devices/virtual/thermal/cooling_device0/cur_state';

		o = s.option(form.Value, 'start_speed', _('Initial Speed'), _('Please enter the initial speed for fan startup.'));
		o.placeholder = '35';

		o = s.option(form.Value, 'max_speed', _('Max Speed'), _('Please enter maximum fan speed.'));
		o.placeholder = '255';

		o = s.option(form.Value, 'start_temp', _('Start Temperature'), _('Please enter the fan start temperature.'));
		o.placeholder = '45';

		return m.render();
	}
});