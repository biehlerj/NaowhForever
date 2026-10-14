# Tracking Reminder

A row of icons for the racial and class tracking you know but have not turned on. Click an icon to start that tracking. Its settings page is Tracking Reminder/Settings, and its switches and defaults come from `ns.FEATURES.trackingReminder`.

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
- A tracking pick with no saved value is on, so turning the feature on reminds you of every tracking you know. Turn one off to opt out.
- The spell IDs are Forever's classic-era IDs: Find Treasure, the hunter tracks, Sense Undead, and Sense Demons.
