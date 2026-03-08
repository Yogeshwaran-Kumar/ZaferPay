import os, re

def find_dart_strings(d):
    hardcoded = []
    # simple match for Text('Something') or Text("Something") 
    pat1 = re.compile(r'Text\(\s*\'([^\'\$]+)\'\s*[,\)]')
    pat2 = re.compile(r'Text\(\s*\"([^\"\$]+)\"\s*[,\)]')
    for r, _, fs in os.walk(d):
        for f in fs:
            if f.endswith('.dart'):
                pth = os.path.join(r, f)
                with open(pth, 'r', encoding='utf-8') as file:
                    for line_num, line in enumerate(file, 1):
                        for m in pat1.findall(line) + pat2.findall(line):
                            if m.strip() and not set(m).issubset(set('0123456789.,-₹%:+ ')):
                                hardcoded.append(f'{f}:{line_num} -> {m}')
    return set(hardcoded)

res = find_dart_strings('c:/Users/dhanu/Downloads/Safe Pay/mobile_app/lib')
with open('c:/Users/dhanu/Downloads/Safe Pay/mobile_app/dart_hardcoded.txt', 'w', encoding='utf-8') as out:
    for r in sorted(list(res)):
        out.write(r + '\n')
print("Done")
