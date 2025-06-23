//
// Copyright (C) 2024 Plank Reloaded Developers
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

using Plank;

namespace Docky {
  public class DesktopDockItem : DockletItem {
    private const string ICON_NAME = "show-desktop";
    private const string ICON_RESOURCE = "resource://" + G_RESOURCE_PATH + "/icons/show-desktop.svg";
    private const string ICON_PATH = ICON_NAME + ";;" + ICON_RESOURCE;
    private ulong scroll_action_handler_id = 0;
    private int workspace_count = 0;
    private int current_workspace = 0;

    private unowned Wnck.Screen? screen;

    private DesktopPreferences desktop_prefs {
      get { return (DesktopPreferences) Prefs; }
    }

    public DesktopDockItem.with_dockitem_file(GLib.File file)
    {
      GLib.Object(Prefs : new DesktopPreferences.with_file(file));
    }

    construct
    {
      initialize_item();
      initialize_wnck();
      setup_workspace_info();

      scroll_action_handler_id = desktop_prefs.notify["EnableScrolling"].connect (() => {
        if (desktop_prefs.EnableScrolling) {
          Text = _("Workspace %d of %d").printf (current_workspace + 1, workspace_count);
        } else {
          Text = _("Show Desktop");
        }
      });

      connect_screen_signals();
    }

    ~DesktopDockItem() {
      screen = null;

      if (scroll_action_handler_id > 0) {
        desktop_prefs.disconnect (scroll_action_handler_id);
        scroll_action_handler_id = 0;
      }

      disconnect_screen_signals();
    }

    private void disconnect_screen_signals () {
      unowned Wnck.Screen screen = Wnck.Screen.get_default ();
      screen.active_workspace_changed.disconnect (handle_workspace_changed);
      screen.workspace_created.disconnect (handle_workspace_count_changed);
      screen.workspace_destroyed.disconnect (handle_workspace_count_changed);
    }

    private void initialize_item() {
      Icon = ICON_PATH;
      Text = _("Show Desktop");
    }

    private void initialize_wnck() {
      screen = Wnck.Screen.get_default();
    }

    private void setup_workspace_info () {
      unowned Wnck.Screen screen = Wnck.Screen.get_default ();

      current_workspace = screen.get_active_workspace () ? .get_number () ?? 0;
      workspace_count = screen.get_workspace_count ();

      if (desktop_prefs.EnableScrolling) {
        Text = _("Workspace %d of %d").printf (current_workspace + 1, workspace_count);
      }
    }

    [CCode (instance_pos = -1)]
    private void handle_workspace_changed (Wnck.Screen screen, Wnck.Workspace? previous) {
      bool changed = false;

      unowned Wnck.Workspace? active_workspace = screen.get_active_workspace ();
      if (active_workspace != null) {
        int new_workspace = active_workspace.get_number ();

        if (new_workspace != current_workspace) {
          current_workspace = new_workspace;
          debug ("Current workspace changed to %d\n", current_workspace);
          changed = true;
        }

        if (changed && desktop_prefs.EnableScrolling) {
          Text = _("Workspace %d of %d").printf (current_workspace + 1, workspace_count);
        }
      }
    }
  
    [CCode (instance_pos = -1)]
    private void handle_workspace_count_changed (Wnck.Screen screen, Wnck.Workspace? workspace) {
      int new_count = screen.get_workspace_count ();

      if (new_count != workspace_count) {
        workspace_count = new_count;
        debug ("Workspace count changed to %d\n", workspace_count);
        Text = _("Workspace %d of %d").printf (current_workspace + 1, workspace_count);
      }
    }

    private void connect_screen_signals () {
      unowned Wnck.Screen screen = Wnck.Screen.get_default ();
      screen.active_workspace_changed.connect_after (handle_workspace_changed);
      screen.workspace_created.connect_after (handle_workspace_count_changed);
      screen.workspace_destroyed.connect_after (handle_workspace_count_changed);
    }

    protected override AnimationType on_clicked(PopupButton button,
                                                Gdk.ModifierType mod,
                                                uint32 event_time) {
      if (button != PopupButton.LEFT)
        return AnimationType.NONE;

      toggle_desktop();
      return AnimationType.BOUNCE;
    }

    private void toggle_desktop() {
      if (screen != null) {
        screen.toggle_showing_desktop(!screen.get_showing_desktop());
      }
    }

    protected override AnimationType on_scrolled (Gdk.ScrollDirection direction, Gdk.ModifierType mod, uint32 event_time) {
      if (!desktop_prefs.EnableScrolling) {
        return AnimationType.NONE;
      }
      int new_workspace = current_workspace;

      int workspace_direction = 0;
      if (direction == Gdk.ScrollDirection.UP || direction == Gdk.ScrollDirection.LEFT) {
        workspace_direction = desktop_prefs.InvertDirection ? 1 : -1;
      } else if (direction == Gdk.ScrollDirection.DOWN || direction == Gdk.ScrollDirection.RIGHT) {
        workspace_direction = desktop_prefs.InvertDirection ? -1 : 1;
      }

      if (workspace_direction > 0) {
        new_workspace = (current_workspace + 1) % workspace_count;
        if (!desktop_prefs.WrapAround && new_workspace < current_workspace) {
          return AnimationType.NONE;
        }
      } else if (workspace_direction < 0) {
        new_workspace = (current_workspace - 1 + workspace_count) % workspace_count;
        if (!desktop_prefs.WrapAround && new_workspace > current_workspace) {
          return AnimationType.NONE;
        }
      }

      switch_to_workspace (new_workspace);

      return AnimationType.NONE;
    }

    private void switch_to_workspace (int workspace_num) {
      if (workspace_num == current_workspace) {
        return;
      }

      unowned Wnck.Screen screen = Wnck.Screen.get_default ();
      unowned Wnck.Workspace? workspace = screen.get_workspace (workspace_num);

      if (workspace != null) {
        workspace.activate (Gtk.get_current_event_time ());
      }
    }

    public override Gee.ArrayList<Gtk.MenuItem> get_menu_items () {
      var items = new Gee.ArrayList<Gtk.MenuItem> ();
      unowned Wnck.Screen screen = Wnck.Screen.get_default ();

      var settings_item = new Gtk.MenuItem ();
      var settings_menu = new Gtk.Menu ();

      var reversed_menu_order = new Gtk.CheckMenuItem.with_mnemonic (_("_Reversed workspace order in menu"));
      reversed_menu_order.active = desktop_prefs.ReversedMenuOrder;
      reversed_menu_order.sensitive = screen.get_workspace_count () > 1;
      reversed_menu_order.activate.connect (() => {
        desktop_prefs.ReversedMenuOrder = !desktop_prefs.ReversedMenuOrder;
      });
      reversed_menu_order.show ();
      settings_menu.add (reversed_menu_order);

      var submenu_separator_item = new Gtk.SeparatorMenuItem ();
      submenu_separator_item.show ();
      settings_menu.add (submenu_separator_item);

      var scroll_action = new Gtk.CheckMenuItem.with_mnemonic (_("_Scroll to switch workspaces"));
      scroll_action.active = desktop_prefs.EnableScrolling;
      scroll_action.activate.connect (() => {
        desktop_prefs.EnableScrolling = !desktop_prefs.EnableScrolling;
      });
      scroll_action.show ();
      settings_menu.add (scroll_action);

      var invert_scroll = new Gtk.CheckMenuItem.with_mnemonic (_("_Invert scrolling direction"));
      invert_scroll.active = desktop_prefs.InvertDirection;
      invert_scroll.sensitive = desktop_prefs.EnableScrolling;
      invert_scroll.activate.connect (() => {
        desktop_prefs.InvertDirection = !desktop_prefs.InvertDirection;
      });
      invert_scroll.show ();
      settings_menu.add (invert_scroll);

      var wrap_around = new Gtk.CheckMenuItem.with_mnemonic (_("_Wrap around when scrolling"));
      wrap_around.active = desktop_prefs.WrapAround;
      wrap_around.sensitive = desktop_prefs.EnableScrolling;
      wrap_around.activate.connect (() => {
        desktop_prefs.WrapAround = !desktop_prefs.WrapAround;
      });
      wrap_around.show ();
      settings_menu.add (wrap_around);

      var settings_label = new Gtk.Label.with_mnemonic (_("_Settings"));
      settings_label.halign = Gtk.Align.START;
      settings_label.valign = Gtk.Align.CENTER;
      settings_item.add (settings_label);
      settings_item.show_all ();

      settings_item.submenu = settings_menu;
      settings_menu.show ();

      items.add (settings_item);

      var separator_item = new Gtk.SeparatorMenuItem ();
      items.add (separator_item);

      for (int i = 0; i < workspace_count; i++) {
        int num = desktop_prefs.ReversedMenuOrder ? (i - workspace_count+1) * -1 : i;
        unowned Wnck.Workspace? workspace = screen.get_workspace (num);
        string name = workspace != null? workspace.get_name () : _("Workspace %d").printf (i + 1);

        var item = new Gtk.MenuItem.with_label (name);

        if (num == current_workspace) {
          var label = item.get_child () as Gtk.Label;
          if (label != null) {
            label.set_markup ("<b>" + label.get_text () + "</b>");
          }
        }

        int workspace_num = num;
        item.activate.connect (() => {
          switch_to_workspace (workspace_num);
        });

        items.add (item);
      }

      return items;
    }
  }
}
