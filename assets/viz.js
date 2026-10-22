/* 학습 자료 그림 공용 엔진.
 *
 * 설계 원칙 (페이지마다 다시 실수하지 않으려고 여기 한 곳에 모았다)
 *  - while 문을 쓰지 않는다. 반복은 상수 경계의 for 만 쓴다
 *  - 폭이나 높이가 0 이하면 아무것도 그리지 않고 즉시 돌아간다
 *  - 움직이는 그림은 화면에 보일 때만 돈다. 화면 밖으로 나가거나 탭이 가려지면 멈춘다
 *  - 색은 전부 CSS 변수에서 읽는다. 다크 모드가 따라온다
 *
 * 쓰는 법
 *   var v = Viz.view('캔버스id', function(w){ return w < 520 ? 250 : 200; }, function(v){ ... });
 *   v.render();                     // 다시 그리기
 *   Viz.animate(v, function(v, t){ ... });   // 움직이는 그림으로 만들기 (t 는 초)
 */
window.Viz = (function(){
  'use strict';

  function cssv(name, fallback){
    var s = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return s || fallback || '#888';
  }

  /** 지금 테마의 색 묶음. 그릴 때마다 새로 읽으므로 테마가 바뀌어도 따라온다. */
  function colors(){
    return {
      text:   cssv('--text', '#222'),
      dim:    cssv('--text-dim', '#777'),
      line:   cssv('--line', '#ddd'),
      accent: cssv('--accent', '#2f6f4f'),
      warn:   cssv('--warn', '#9a5b12'),
      sf:     cssv('--surface', '#fff'),
      sf2:    cssv('--surface-2', '#f3f1ed')
    };
  }

  /**
   * 캔버스 하나를 폭에 맞춰 관리한다.
   * heightOf(w) 로 높이를 정하고, draw(view) 로 그린다. draw 는 지운 캔버스를 받는다.
   */
  function view(id, heightOf, draw){
    var cv = typeof id === 'string' ? document.getElementById(id) : id;
    if (!cv) return null;

    var v = { cv: cv, ctx: cv.getContext('2d'), w: 0, h: 0, t: 0, c: colors() };

    function fit(){
      var w = cv.clientWidth;
      if (!(w > 0)) return false;
      var h = heightOf(w);
      if (!(h > 0)) return false;
      if (cv.width !== w || cv.height !== h){ cv.width = w; cv.height = h; }
      v.w = w; v.h = h;
      return true;
    }

    v.render = function(){
      if (!(v.w > 0) || !(v.h > 0)) return;
      v.c = colors();
      v.ctx.clearRect(0, 0, v.w, v.h);
      draw(v);
    };

    var lastW = -1;
    new ResizeObserver(function(){
      if (cv.clientWidth !== lastW){
        lastW = cv.clientWidth;
        if (fit()) v.render();
      }
    }).observe(cv);

    if (fit()) v.render();
    return v;
  }

  /**
   * 움직이는 그림으로 만든다. step(view, t) 가 매 프레임 불린다.
   * 화면에 보일 때만 돌고, 보이지 않으면 멈춘다. 페이지가 알아서 할 일은 없다.
   */
  function animate(v, step){
    if (!v) return null;
    var raf = 0, visible = false;

    function tick(){
      raf = 0;
      if (!visible || document.hidden) return;      // 조건이 깨지면 루프가 끝난다
      v.t += 1 / 60;
      if (v.t > 1e6) v.t = 0;
      if (step) step(v, v.t);
      v.render();
      raf = requestAnimationFrame(tick);
    }
    function run(on){
      if (on){ if (!raf && visible && !document.hidden) raf = requestAnimationFrame(tick); }
      else if (raf){ cancelAnimationFrame(raf); raf = 0; }
    }

    new IntersectionObserver(function(es){
      visible = es[0].isIntersecting;
      run(visible);
    }, { threshold: 0.15 }).observe(v.cv);

    document.addEventListener('visibilitychange', function(){
      run(!document.hidden && visible);
    });

    return { stop: function(){ run(false); }, start: function(){ run(true); } };
  }

  /* ── 그리기 도구 ───────────────────────────────── */

  function text(ctx, s, x, y, color, size, align){
    ctx.font = (size || 12) + 'px ui-monospace, Consolas, monospace';
    ctx.fillStyle = color;
    ctx.textAlign = align || 'left';
    ctx.textBaseline = 'middle';
    ctx.fillText(s, x, y);
  }

  function roundRect(ctx, x, y, w, h, r){
    if (!(w > 0) || !(h > 0)) return;
    var rr = Math.min(r || 6, w / 2, h / 2);
    ctx.beginPath();
    ctx.moveTo(x + rr, y);
    ctx.arcTo(x + w, y, x + w, y + h, rr);
    ctx.arcTo(x + w, y + h, x, y + h, rr);
    ctx.arcTo(x, y + h, x, y, rr);
    ctx.arcTo(x, y, x + w, y, rr);
    ctx.closePath();
  }

  function arrow(ctx, x0, y0, x1, y1, color, width){
    ctx.strokeStyle = color; ctx.fillStyle = color;
    ctx.lineWidth = width || 2; ctx.lineCap = 'round';
    ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
    var a = Math.atan2(y1 - y0, x1 - x0), s = 7;
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x1 - s * Math.cos(a - 0.5), y1 - s * Math.sin(a - 0.5));
    ctx.lineTo(x1 - s * Math.cos(a + 0.5), y1 - s * Math.sin(a + 0.5));
    ctx.closePath(); ctx.fill();
  }

  /** 흐르는 지면. offset 이 커질수록 왼쪽으로 흐른다. */
  function ground(ctx, x0, x1, y, offset, c){
    if (!(x1 > x0)) return;
    ctx.strokeStyle = c.line; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(x0, y); ctx.lineTo(x1, y); ctx.stroke();
    var step = 30;
    var start = x0 - (((offset % step) + step) % step) - step;
    for (var k = 0; k < 80; k++){                  // 루프 경계는 상수
      var x = start + k * step;
      if (x > x1) break;
      if (x >= x0){
        ctx.beginPath(); ctx.moveTo(x, y + 3); ctx.lineTo(x - 8, y + 12); ctx.stroke();
      }
    }
  }

  /**
   * 달리는 사람. phase 0~1 이 한 걸음 주기.
   * 발이 땅에 닿아 있으면 그 x 좌표를 돌려준다 (미끄러짐 표시에 쓴다).
   */
  function runner(ctx, x, groundY, phase, stride, c, facing){
    var hip = groundY - 48;
    var dir = facing === undefined ? 1 : facing;
    ctx.lineWidth = 3; ctx.lineCap = 'round';
    ctx.strokeStyle = c.text;

    ctx.beginPath(); ctx.moveTo(x, hip); ctx.lineTo(x, hip - 26); ctx.stroke();
    ctx.beginPath(); ctx.arc(x + dir * 2, hip - 34, 7, 0, Math.PI * 2);
    ctx.fillStyle = c.text; ctx.fill();

    var contact = null;
    for (var i = 0; i < 2; i++){                   // 다리 둘
      var p = phase + i * 0.5;
      var t = (p - Math.floor(p)) * Math.PI * 2;
      var lift = Math.max(0, Math.cos(t));
      var fx = x + Math.sin(t) * stride / 2;
      var fy = groundY - lift * 16;
      var down = lift < 0.02;
      ctx.strokeStyle = down ? c.accent : c.text;
      ctx.beginPath(); ctx.moveTo(x, hip); ctx.lineTo(fx, fy); ctx.stroke();
      ctx.beginPath(); ctx.ellipse(fx, fy, 7, 3.5, 0, 0, Math.PI * 2);
      ctx.fillStyle = down ? c.accent : c.dim; ctx.fill();
      if (down && contact === null) contact = fx;
    }
    return contact;
  }

  /** 위에서 본 캐릭터. bodyDeg 는 몸이 보는 각(0 이 위쪽). */
  function topDownBody(ctx, cx, cy, r, bodyDeg, c, color){
    var a = (bodyDeg - 90) * Math.PI / 180;
    ctx.strokeStyle = color || c.text; ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, Math.PI * 2); ctx.stroke();
    // 코 — 보는 쪽
    ctx.beginPath();
    ctx.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r);
    ctx.lineTo(cx + Math.cos(a) * (r + 10), cy + Math.sin(a) * (r + 10));
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(cx + Math.cos(a) * (r + 10), cy + Math.sin(a) * (r + 10), 3, 0, Math.PI * 2);
    ctx.fillStyle = color || c.text; ctx.fill();
  }

  /** 각도를 -180~180 으로 접는다. */
  function wrap180(d){
    var x = ((d + 180) % 360 + 360) % 360 - 180;
    return x;
  }

  return {
    view: view, animate: animate, colors: colors, cssv: cssv,
    text: text, roundRect: roundRect, arrow: arrow,
    ground: ground, runner: runner, topDownBody: topDownBody, wrap180: wrap180
  };
})();
