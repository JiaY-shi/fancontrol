'use strict';
'require view';
'require fs';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function () {
		var m, s, o, v;

		m = new form.Map('fancontrol', _('Fan General Control Script'));
		s = m.section(form.TypedSection, 'fancontrol', _('Settings'));
		s.anonymous = true;

		o = s.option(form.Flag, 'enabled', _('Enabled'), _('Enabled'));
		o.rmempty = false;

		o = s.option(form.Value, 'thermal_file', _('Thermal File'), _('Thermal File'));
		o.placeholder = '/sys/devices/virtual/thermal/thermal_zone0/temp';

		o = s.option(form.Value, 'fan_file', _('Fan File'), _('Fan Speed File'));
		o.placeholder = '/sys/devices/virtual/thermal/cooling_device0/cur_state';

		o = s.option(form.Value, 'thresholds', _('Temperature'), _('Please enter the temperature gradient values, separated by comma.'));
		o.placeholder = '100,90,80,75,60,65,60,50,45';

		o = s.option(form.Value, 'speeds', _('Speed'), _('Please enter the speed step values, separated by comma.'));
		o.placeholder = '255,220,185,150,115,95,80,60,30';

		return m.render();
	}
});