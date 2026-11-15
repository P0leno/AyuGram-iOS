# Custom Branding & Icons

Drop custom `.png` or `.jpg` / `.jpeg` icons (recommended `1024x1024` square) in this directory and reference them in `../branding.json`:

```json
{
  "display_name": "MyGram",
  "badge_title": "MY",
  "hide_client_branding": true,
  "default_icon": "MyCustomIcon",
  "icons": [
    { "id": "MyCustomIcon", "title": "My Icon", "source": "custom_icons/my_icon.png" },
    { "id": "AyuClassic", "title": "AyuClassic", "source": "icons.json:AyuClassic" }
  ]
}
```

You can also override `app_name`, `custom_icon_url`, `custom_icon_name`, and `hide_branding` directly when triggering the GitHub Actions workflow (`workflow_dispatch`).
