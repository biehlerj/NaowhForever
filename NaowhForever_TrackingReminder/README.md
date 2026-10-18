# Tracking Reminder

A row of icons for the racial and class tracking you know but have not turned on. Click an icon to start that tracking. Players see it as Racial and Class Tracking. Its settings page is Racial and Class Tracking/Settings, and its switches and defaults come from `ns.FEATURES.trackingReminder`.

## Layout

```
NaowhForever_TrackingReminder/
  NaowhForever_TrackingReminder.toc   the addon; lists only TrackingReminder.xml
  TrackingReminder.xml                every file, in load order
  TrackingReminder.lua                the settings and the module table (ns.TrackingReminder)
  Data/
    Spells.lua                        racial and class tracking spell IDs (TR.Data)
  UI/
    Reminder.lua                      the HUD row of secure icons and its mover (TR.Look)
    SettingsPage.lua                  the settings page, declared as cards, with a preview
  README.md                           this file
```

## Why

- Forever can track more than one thing at once, so each missing racial or class tracking gets its own icon. A hunter has eight, and three mouse buttons cannot cast them all.
- Each icon is a secure button. Its spell is set out of combat, and the row hides when combat starts, so combat never changes a secure attribute.
- The buttons are built on first enable, and tracking events are registered only while the feature is on.
- A tracking pick with no saved value is off. Turning racial or class tracking on reminds you of nothing until you turn that spell on.
- The spell IDs are Forever's classic-era IDs: Find Treasure, the hunter tracks, Sense Undead, and Sense Demons.
- The row homes at 260, 170 so it sits above the Professions gather icon at 260, 120, without reading that addon.
- A minimap slot is turned on with SetTracking, so Unlock Mode cannot toggle it off. A spell with no slot is cast from the secure button.
- GetTrackingInfo is read as a table or as the older tuple.
