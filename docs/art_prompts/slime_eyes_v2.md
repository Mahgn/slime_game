# Slime eyes v2, 2026-09-24

Mode: built-in image_gen edit. User attachment saved as docs/art_refs/slime_eyes_user_reference.png. The source is a visual reference only and is not used in the runtime scene. Front and side candidate v1 PNGs were the edit targets. Because direct local image references failed in the built-in tool, scaled context views of those targets were displayed in the conversation. The original v1 PNGs remain in the project. The back view stays at v1 because it has no eyes.

## Front edit prompt

Use case: precise-object-edit
Input images: Image 1 is the user's eye-design REFERENCE (two dark forest-green oval eyes with one large white circular glint and one smaller white dot inside each). Image 2 is the EDIT TARGET, the mint-turquoise cube slime character on a transparent background.
Primary request: edit ONLY the pair of eyes on Image 2 so they match the visual language of Image 1. Replace both current pale cream eyeballs and dark pupils with two soft dark-green oval eye patches integrated into the gel face. Each dark-green oval must contain one large clean white round highlight near its upper-left and one smaller clean white dot toward the right/lower-right, echoing the reference. Preserve the current two-eye placement, approximate size, spacing and cute expression.
Must preserve exactly: the slime's entire rounded-cube silhouette, mint and turquoise body colors, jelly folds, bubbles, luminous core, top surface, soft rim, framing, pose, proportions, viewing angle and transparent background. Do not change the body, add limbs or accessories, add a mouth, add text, or add a floor or cast shadow. Retain the polished stylized 3D game-render quality of the original slime image. The green eye shapes and white glints should be simple and clearly readable at small in-game size. Output the full isolated character on a genuinely transparent background.

## Side edit prompt

Use case: precise-object-edit
Input images in order: Image 1 is the newly edited FRONT view of the mint slime and establishes the exact new eye treatment. Image 2 is the user's eye-design reference. Image 3 is the SIDE-view EDIT TARGET of that same slime.
Primary request: edit ONLY the single visible eye on Image 3 so it matches the new front-view eyes and the user's reference. Replace the current pale cream eyeball and dark pupil with one soft dark forest-green oval eye patch integrated into the gel, located in the exact same place on the forward-facing edge. Inside it, put one large clean white round highlight near the upper-left and one smaller clean white dot toward the right/lower-right. Preserve the clear side profile and direction of gaze. Do not invent a second eye in this profile.
Must preserve exactly: the side-view body's silhouette, gel folds, mint-turquoise color, luminous core, bubbles, top, base, proportions, view angle, framing, painterly 3D render quality and genuine transparent background. No other changes, no mouth, limbs, accessories, text, floor or shadow. Output one full isolated side-view character.
