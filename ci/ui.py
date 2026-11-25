import subprocess, sys, re, time
def sh(*a): return subprocess.run(["adb","shell",*a],capture_output=True,text=True).stdout
def dump():
    sh("uiautomator","dump","/sdcard/ui.xml")
    return sh("cat","/sdcard/ui.xml")
def find(text=None, desc=None):
    x = dump()
    for m in re.finditer(r'<node [^>]*>', x):
        n = m.group(0)
        t = re.search(r' text="([^"]*)"', n); d = re.search(r' content-desc="([^"]*)"', n)
        if (text and t and t.group(1)==text) or (desc and d and d.group(1)==desc):
            b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', n)
            x1,y1,x2,y2 = map(int,b.groups()); return (x1+x2)//2,(y1+y2)//2
    return None
def tap(text=None, desc=None):
    p = find(text, desc)
    if not p: print("NOT FOUND", text or desc); return False
    sh("input","tap",str(p[0]),str(p[1])); print("tapped", text or desc, p); return True
if __name__=="__main__":
    k,v = sys.argv[1], sys.argv[2]
    sys.exit(0 if (tap(text=v) if k=="text" else tap(desc=v)) else 1)
