/*
 * tuibox_stub.c: the C half of the Ada binding (see tuibox.ads).
 *
 * tuibox.h is header-only and defines its functions non-static, so this
 * is the one translation unit that includes it. The stub gives Ada what
 * it cannot reach directly: the macros, the fields of ui_t (opaque to
 * Ada, its layout depends on termios), and the ui_loop read loop.
 */

#include <errno.h>
#include <poll.h>
#include <signal.h>

#include "tuibox.h"

/* Keep in sync with Tuibox.Event_Kind. */
enum tb_event { TB_CLOSED, TB_INPUT, TB_RESIZED };

/* ui_new leaves ISIG on: without these, Ctrl-C kills the process and
 * leaves the terminal raw, in the alternate screen, with mouse reporting
 * on. A signal only sets a flag; tb_next_event acts on it. */
static const int tb_signals[] = { SIGINT, SIGTERM, SIGWINCH };
static struct sigaction tb_saved[3];
static volatile sig_atomic_t tb_closing, tb_resized;

static void tb_on_signal(int sig){
  if(sig == SIGWINCH) tb_resized = 1;
  else tb_closing = 1;
}

/* NULL when stdin/stdout are not a terminal: ui_new would otherwise read
 * an undefined window size. */
ui_t *tb_new(int screen){
  struct sigaction sa;
  ui_t *u;
  int i;

  if(!isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO)) return NULL;
  u = calloc(1, sizeof(ui_t));
  if(u == NULL) return NULL;

  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = tb_on_signal;
  sigemptyset(&sa.sa_mask);
  for(i = 0; i < 3; i++) sigaction(tb_signals[i], &sa, &tb_saved[i]);

  tb_closing = tb_resized = 0;
  ui_new(screen, u);
  return u;
}

void tb_free(ui_t *u){
  int i;

  ui_free(u);
  free(u);
  fflush(stdout);
  for(i = 0; i < 3; i++) sigaction(tb_signals[i], &tb_saved[i], NULL);
}

/* Length of the first event in s: a mouse sequence up to its final M or m,
 * anything else up to the next escape. */
static int tb_event_length(const char *s, int n){
  int mouse = n >= 3 && strncmp(s, "\x1b[<", 3) == 0;
  int len = 1;

  while(len < n && s[len] != '\x1b'){
    if(mouse && (s[len] == 'M' || s[len] == 'm')) return len + 1;
    len++;
  }
  return len;
}

/* True for s = button;x;y followed by M or m. */
static int tb_mouse_args_ok(const char *s){
  int i;

  for(i = 0; i < 3; i++){
    size_t digits = strspn(s, "0123456789");

    if(digits == 0) return 0;
    s += digits;
    if(i < 2 && *s++ != ';') return 0;
  }
  return *s == 'M' || *s == 'm';
}

/* _ui_update strtok()s an unterminated copy of its input and dereferences
 * the tokens unchecked, and handles one mouse event per call. Hand it one
 * NUL-terminated event at a time (the NUL is counted, so its copy keeps
 * it) and drop mouse sequences that are malformed or cut short by the
 * read. */
static void tb_update(const char *buf, int n, ui_t *u){
  char ev[64 + 1];
  int i = 0;

  while(i < n){
    int len = tb_event_length(buf + i, n - i);

    memcpy(ev, buf + i, len);
    ev[len] = '\0';
    i += len;

    if(strncmp(ev, "\x1b[<", 3) == 0 && !tb_mouse_args_ok(ev + 3)) continue;
    _ui_update(ev, len + 1, u);
  }
}

/* ui_loop plus ui_update, with signals as events. */
int tb_next_event(ui_t *u){
  char buf[64];

  for(;;){
    struct pollfd p = { STDIN_FILENO, POLLIN, 0 };
    int r, n;

    if(tb_closing) return TB_CLOSED;
    if(tb_resized){
      tb_resized = 0;
      ioctl(STDOUT_FILENO, TIOCGWINSZ, &(u->ws));
      return TB_RESIZED;
    }

    /* The timeout covers a signal landing just before poll. */
    r = poll(&p, 1, 250);
    if(r < 0 && errno != EINTR) return TB_CLOSED;
    if(r <= 0) continue;

    n = read(STDIN_FILENO, buf, sizeof(buf));
    if(n < 0 && errno == EINTR) continue;
    if(n <= 0) return TB_CLOSED;

    tb_update(buf, n, u);
    return TB_INPUT;
  }
}

/* What ui_clear does to the boxes, without its ui_free/ui_new: stays in
 * the alternate screen and keeps the key listeners. */
void tb_clear_boxes(ui_t *u){
  ui_box_t *b;
  int i;

  vec_foreach(&(u->b), b, i){
    free(b->cache);
    free(b);
  }
  vec_clear(&(u->b));
  u->click = NULL;
  u->id = 0;
}

/* Bytes the draw callback may write to out, NUL included. ui_add hands
 * it the MAXCACHESIZE cache; ui_draw_one a buffer of twice the cached
 * output's length. */
int tb_draw_capacity(ui_box_t *b, char *out){
  return out == b->cache ? MAXCACHESIZE : (int)strlen(b->cache) * 2;
}

int tb_sizeof_box(void){ return sizeof(ui_box_t); }

int tb_columns(ui_t *u){ return u->ws.ws_col; }
int tb_rows(ui_t *u){ return u->ws.ws_row; }
int tb_box_count(ui_t *u){ return u->b.length; }
ui_box_t *tb_get(int id, ui_t *u){ return ui_get(id, u); }
void tb_set_screen(int s, ui_t *u){ ui_screen(s, u); }
int tb_mouse(ui_t *u){ return u->mouse; }
int tb_scroll(ui_t *u){ return u->scroll; }
void tb_set_can_scroll(int on, ui_t *u){ u->canscroll = on; }
