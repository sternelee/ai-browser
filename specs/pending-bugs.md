# PENDING TASKS and BUGS

[ ] 'Page context available' im not sure if its taking all the text in the page correctly, please review, it doesnt seem like it, we need to do smart context engineering to optimize context but its important that we give all the important info to the model
[ ] In the AI responses, before responding the 3 dots are duplicated, not animated properly, and badly layouted. Also after the AI responses the message flickers in a loop forever, and we still see one of the 3 dots moving up and down
[ ] URL bar not working well, its not updating the url sometimes after clicking a link and stuff, shows the previous page url, should always show the current page, its critical that this is correct
[ ] The AI is not utilizing well all resources, the app barely has any cpu and memory usage when i ask a question. Also we have the callback streaming disabled bc it doesnt work, but would be better to remove it alltogether. Let's make sure this is robust, research internet for references.
[ ] Overlay panels like history, settings, etc show a weird square with blue accent border wrapping them
[ ] If there is no internet connection the page gets reloaded in a loop forever, we need a page for internet connection missing.
[ ] Let's ensure there are 0 warnings when building
[ ] Show favicon in history panel, autofill, bookmarks panel
[ ] Open in new tab or cmd + link click should selected the new tab automatically
[ ] Does full screen videos work?
[ ] Double clicking window should expand the window to the whole screen and double clicking again should restore the previous size of the window
[ ] The keyboard gets "locked" for some specific reason, cant select inputs from the browser app or even from pages like the google input, and like pressing "spacebar" to stop a video is also locked and doesnt work

--

Fix all the pending tasks and bugs in the pending bugs spec. One by one, first research files and internet for refs, then spin up a subagent to implement a solution, check the task/bug as for review and then move to the next one, 1 by 1, do all of them.
