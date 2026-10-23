"""Testa no AVD com desligamento real da rede entre download e inferência."""
from pathlib import Path
import json
import subprocess
import sys
ROOT=Path(__file__).resolve().parents[1]
ADB=['adb','-s','emulator-5554','shell']
def adb(*args):
    return subprocess.run(ADB+list(args),capture_output=True,text=True,check=True).stdout.strip()
def main():
    report=ROOT/'reports';report.mkdir(exist_ok=True)
    flutter=ROOT/'.tools/flutter/bin/flutter.bat'
    command=[str(flutter),'drive','--driver','test_driver/integration_test.dart','--target','integration_test/reader_flow_test.dart','-d','emulator-5554','--dart-define=OFFLINE_AUDIT=true']
    original={'airplane':adb('cmd','connectivity','airplane-mode'),
              'wifi':adb('settings','get','global','wifi_on'),'data':adb('settings','get','global','mobile_data')}
    audit={'original':original,'disabledBeforeInference':False}
    try:
        adb('cmd','connectivity','airplane-mode','disable');adb('svc','wifi','enable');adb('svc','data','enable')
        with (report/'android-integration.log').open('w',encoding='utf-8') as log:
            p=subprocess.Popen(command,cwd=ROOT/'app',stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace')
            for line in p.stdout:
                log.write(line);log.flush()
                if 'MODELS_READY_OFFLINE' in line:
                    adb('cmd','connectivity','airplane-mode','enable');adb('svc','wifi','disable');adb('svc','data','disable')
                    state=adb('cmd','connectivity','airplane-mode')
                    if state!='enabled':raise RuntimeError('Modo avião não confirmado')
                    audit.update({'disabledBeforeInference':True,'airplaneDuringInference':state,'wifiDuringInference':adb('cmd','wifi','status')})
                    print('Rede desligada antes da inferência; aguardando confirmação nativa.',flush=True)
            code=p.wait()
        audit['exitCode']=code
        if code==0 and not audit['disabledBeforeInference']:raise RuntimeError('Teste terminou sem passar pelo gate offline')
        print(f'Integração concluída: exit={code}',flush=True)
        return code
    finally:
        adb('cmd','connectivity','airplane-mode','enable' if original['airplane']=='enabled' else 'disable')
        adb('svc','wifi','enable' if original['wifi']=='1' else 'disable')
        adb('svc','data','enable' if original['data']=='1' else 'disable')
        audit['restored']=True
        (report/'network-audit.json').write_text(json.dumps(audit,indent=2,ensure_ascii=False),encoding='utf-8')
if __name__=='__main__':sys.exit(main())
