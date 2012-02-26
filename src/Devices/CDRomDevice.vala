/*-
 * Copyright (c) 2011-2012       Scott Ringwelski <sgringwe@mtu.edu>
 *
 * Originally Written by Scott Ringwelski for BeatBox Music Player
 * BeatBox Music Player: http://www.launchpad.net/beat-box
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

using GPod;
using Gee;

public class BeatBox.CDRomDevice : GLib.Object, BeatBox.Device {
	LibraryManager lm;
	LibraryWindow lw;
	Mount mount;
	GLib.Icon icon;
	
	CDRipper ripper;
	Media media_being_ripped;
	int current_list_index;
	
	bool _is_transferring;
	bool user_cancelled;
	
	string current_operation;
	double current_song_progress;
	int index;
	int total;
	
	LinkedList<int> medias;
	LinkedList<int> list;
	
	public CDRomDevice(LibraryManager lm, Mount mount) {
		this.lm = lm;
		this.lw = lm.lw;
		this.mount = mount;
		this.icon = mount.get_icon();
		
		list = new LinkedList<int>();
		medias = new LinkedList<int>();
		media_being_ripped = null;
	}
	
	public DevicePreferences get_preferences() {
		return new DevicePreferences(get_unique_identifier());
	}
	
	public bool start_initialization() {
		return true;
	}
	
	public void finish_initialization() {
		device_unmounted.connect( () => {
			stdout.printf("unmount in cdromdevice..\n");
			foreach(int i in medias) {
				Media m = lm.media_from_id(i);
				stdout.printf("blah\n");
				m.unique_status_image = null;
				lm.update_media(m, false, false);
			}
			stdout.printf("unmount finished\n");
		});
		
		lm.progress_cancel_clicked.connect(cancel_transfer);
		
		try {
			Thread.create<void*>(finish_initialization_thread, false);
		}
		catch(GLib.ThreadError err) {
			stdout.printf("ERROR: Could not create thread to finish ipod initialization: %s \n", err.message);
		}
	}
	
	void* finish_initialization_thread() {
		var tMedias = CDDA.getMediaList(mount.get_default_location());
		lm.add_medias(tMedias, false);
		foreach(var s in tMedias)
			medias.add(s.rowid);
		
		Idle.add( () => {
			initialized(this);
			
			return false;
		});
		
		return null;
	}
	
	public string getContentType() {
		return "cdrom";
	}
	
	public string getDisplayName() {
		return mount.get_name();
	}
	
	public void setDisplayName(string name) {
		
	}
	
	public string get_fancy_description() {
		return "No Description";
	}
	
	public void set_mount(Mount mount) {
		this.mount = mount;
	}
	
	public Mount get_mount() {
		return mount;
	}
	
	public string get_path() {
		return mount.get_default_location().get_path();
	}
	
	string get_uri() {
		return mount.get_default_location().get_uri();
	}
	
	public void set_icon(GLib.Icon icon) {
		this.icon = icon;
	}
	
	public GLib.Icon get_icon() {
		return icon;
	}
	
	public uint64 get_capacity() {
		return (uint64)0;
	}
	
	public string get_fancy_capacity() {
		return "Unknown capacity";
	}
	
	public uint64 get_used_space() {
		return (uint64)0;
	}
	
	public uint64 get_free_space() {
		return (uint64)0;
	}
	
	public void unmount() {
		
	}
	
	public void eject() {
		
	}
	
	public void get_device_type() {
		
	}
	
	public bool supports_podcasts() {
		return false;
	}
	
	public bool supports_audiobooks() {
		return false;
	}
	
	public Collection<int> get_medias() {
		return medias;
	}
	
	public Collection<int> get_songs() {
		return new LinkedList<int>();
	}
	
	public Collection<int> get_podcasts() {
		return new LinkedList<int>();
	}
	
	public Collection<int> get_audiobooks() {
		return new LinkedList<int>();
	}
	
	public Collection<int> get_playlists() {
		return new LinkedList<int>();
	}
	
	public Collection<int> get_smart_playlists() {
		return new LinkedList<int>();
	}
	
	public bool sync_medias(LinkedList<int> list) {
		stdout.printf("Ripping not supported on CDRom's.\n");
		return false;
	}
	
	public bool sync_playlists(LinkedList<int> list) {
		return false;
	}
	
	public bool will_fit(LinkedList<int> list) {
		return false;
	}
	
	public bool transfer_to_library(LinkedList<int> list) {
		this.list = list;
		
		// do checks to make sure we can go on
		if(!GLib.File.new_for_path(lm.settings.getMusicFolder()).query_exists()) {
			lw.doAlert("Could not find Music Folder", "Please make sure that your music folder is accessible and mounted before importing the CD.");
			return false;
		}
		
		if(lm.doing_file_operations()) {
			lw.doAlert("BeatBox is already doing an import", "Please wait until BeatBox is finished with the current import before importing the CD.");
			return false;
		}
		
		ripper = new CDRipper(lm, get_uri(), medias.size);
		if(!ripper.initialize()) {
			stdout.printf("Could not create CD Ripper\n");
			return false;
		}
		
		current_list_index = 0;
		Media s = lm.media_from_id(list.get(current_list_index));
		media_being_ripped = s;
		s.showIndicator = true;
		lm.update_media(s, false, false);
		
		// initialize gui feedback
		index = 0;
		total = list.size;
		current_operation = "Ripping track 1: <b>" + s.title.replace("&", "&amp;") + "</b>" + ((s.artist != "Unknown Artist") ? " by " : "") + "<b>" + s.artist.replace("&", "&amp;") + "</b>" + ((s.album != "Unknown Album") ? " on " : "") + "<b>" + s.album.replace("&", "&amp;") + "</b>";
		_is_transferring = true;
		lm.start_file_operations(current_operation);
		lw.updateSensitivities();
		Timeout.add(500, doProgressNotificationWithTimeout);
		user_cancelled = false;
		ripper.progress_notification.connect( (progress) => {
			current_song_progress = progress;
		});
		
		// connect callbacks
		ripper.media_ripped.connect(mediaRipped);
		ripper.error.connect(ripperError);
		
		// start process
		ripper.ripMedia(s.track, s);
		
		// this refreshes so that the spinner shows
		ViewWrapper vw = ((ViewWrapper)lm.lw.sideTree.getWidget(lm.lw.sideTree.devices_cdrom_iter));
		vw.doUpdate(vw.currentView, medias, true, true, false);
		
		// this spins the spinner for the current media being imported
		Timeout.add(100, pulser);
		return false;
	}
	
	public void mediaRipped(Media s) {
		s.showIndicator = false;
		lm.convert_temp_to_permanent(s.rowid);
		
		if(GLib.File.new_for_uri(s.uri).query_exists()) {
			try {
				s.file_size = (int)(GLib.File.new_for_uri(s.uri).query_info("*", FileQueryInfoFlags.NONE).get_size()/1000000);
			}
			catch(Error err) {
				s.file_size = 5; // best guess
				stdout.printf("Could not get ripped media's file_size: %s\n", err.message);
			}
		}
		else {
			stderr.printf("Just-imported song from CD could not be found at %s\n", s.uri);
			//s.file_size = 5; // best guess
		}
		
		lm.update_media(s, true, true);
		
		// do it again on next track
		if(current_list_index < (list.size - 1) && !user_cancelled) {
			++current_list_index;
			Media next = lm.media_from_id(list.get(current_list_index));
			media_being_ripped = next;
			ripper.ripMedia(next.track, next);
			
			next.showIndicator = true;
			lm.update_media(next, false, false);
			
			++index;
			current_operation = "<b>Importing</b> track " + next.track.to_string() + ": <b>" + next.title.replace("&", "&amp;") + "</b>" + ((next.artist != "Unknown Artist") ? " by " : "") + "<b>" + next.artist.replace("&", "&amp;") + "</b>" + ((next.album != "Unknown Album") ? " on " : "") + "<b>" + next.album.replace("&", "&amp;") + "</b>";
		}
		else {
			lm.finish_file_operations();
			media_being_ripped = null;
			_is_transferring = false;
			
			if(!lw.has_toplevel_focus) {
				try {
					lm.lw.notification.close();
					lm.lw.notification.update("Import Complete", "BeatBox has finished importing " + (current_list_index + 1).to_string() + " songs from Audio CD", "beatbox");
					
					var beatbox_icon = Icons.BEATBOX_ICON.render(Gtk.IconSize.DIALOG, null);
					lm.lw.notification.set_image_from_pixbuf(beatbox_icon);
					
					lm.lw.notification.show();
					lm.lw.notification.set_timeout(5000);
				}
				catch(GLib.Error err) {
					stderr.printf("Could not show notification: %s\n", err.message);
				}
			}
		}
	}
	
	public bool pulser() {
		if(media_being_ripped != null) {
			media_being_ripped.pulseProgress++;
			
			var updated = new LinkedList<int>();
			updated.add(media_being_ripped.rowid);
			((DeviceViewWrapper)lm.lw.sideTree.getWidget(lm.lw.sideTree.devices_cdrom_iter)).list.update_medias(updated);
			
			return true;
		}
		else {
			return false;
		}
	}
	
	public bool is_syncing() {
		return false;
	}
	
	public bool is_transferring() {
		return _is_transferring;
	}
	
	public void cancel_sync() {
		
	}
	
	public void cancel_transfer() {
		user_cancelled = true;
		current_operation = "<b>Cancelling</b> remaining imports...";
	}
	
	public void ripperError(string err, Gst.Message message) {
		if(err == "missing element") {
			if(message.get_structure() != null && Gst.is_missing_plugin_message(message)) {
					InstallGstreamerPluginsDialog dialog = new InstallGstreamerPluginsDialog(lm, lw, message);
					dialog.show();
				}
		}
	}
	
	public bool doProgressNotificationWithTimeout() {
		lw.progressNotification(current_operation.replace("&", "&amp;"), (double)(((double)index + current_song_progress)/((double)total)));
		
		if(index < total && (is_transferring())) {
			return true;
		}
		
		return false;
	}
}