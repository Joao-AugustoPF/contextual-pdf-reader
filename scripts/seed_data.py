"""Entradas autorais explícitas (agente), CC0. Não são rótulos humanos validados."""
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
# lemma | sentido | traduções | protótipo contextual (alvo entre colchetes)
ROWS = '''light|illumination|luz|The [light] from the lamp filled the bedroom.
light|lightweight|leve,leve em recursos|A [light] backpack is easy to carry.
bank|financial|banco|The [bank] approved our mortgage application.
bank|river_edge|margem,beira|We walked along the muddy [bank] of the stream.
charge|fee|cobrança,taxa,cobrar|There is a service [charge] on the bill.
charge|electricity|carga,carregar|The battery has enough [charge] for an hour.
charge|accusation|acusação,acusar|The criminal [charge] was dismissed in court.
run|execute|executar,rodar|Please [run] the script in the terminal.
run|jog|correr,corrida|The athletes [run] around the stadium.
give up|stop|desistir,abandonar,desistiu,desisti|Do not [give up] learning the violin.
give in|yield|ceder,cedeu,render|The negotiator refused to [give in] to pressure.
give away|donate|doar,distribuir,dar|They will [give away] old clothes to charity.
look up|search|pesquisar,consultar,procurar|You can [look up] the address in the directory.
look after|care|cuidar,cuidar de|Nurses [look after] patients in the hospital.
turn down|reject|recusar,rejeitar|He might [turn down] the invitation to dinner.
turn down|reduce|diminuir,abaixar,reduzir|Please [turn down] the loud radio.
set up|establish|configurar,montar,criar,instalar|We need to [set up] a new database server.
carry on|continue|continuar,prosseguir|The musicians [carry on] playing despite the rain.
run into|encounter|encontrar,encontrei,esbarrar|I sometimes [run into] an old neighbor at the market.
thread|computing|thread,linha de execução|A worker [thread] processes tasks in parallel.
thread|fiber|fio,linha|Pass the [thread] through the sewing needle.
framework|software|framework,estrutura|The web [framework] provides routing and templates.
framework|structure|estrutura,arcabouço|The steel [framework] supports the roof.
race condition|concurrency|condição de corrida,condição de disputa|Two concurrent writes can cause a [race condition].
lock|mutex|bloqueio,trava,mutex|Acquire the [lock] before modifying shared memory.
lock|door|fechadura,tranca|The key will not fit the rusty [lock].
deploy|publish|implantar,publicar,implante,implementar|We [deploy] the website to production every Friday.
build|software|compilação,compilar,construir|The nightly [build] failed because of a syntax error.
build|construct|construir,construção|They [build] wooden houses in this village.
branch|git|ramificação,branch,ramo|Merge the feature [branch] into the main repository.
branch|tree|galho,ramo|A bird landed on the highest [branch].
release|version|versão,lançamento,lançar|This software [release] includes security patches.
release|free|libertar,soltar,liberação|The shelter will [release] the recovered eagle.
state|condition|estado|The application [state] is persisted to disk.
state|territory|estado|California is a large [state] on the Pacific coast.
on the fly|dynamic|dinamicamente,em tempo real,na hora|The compiler optimizes code [on the fly].
out of the box|ready|pronto para uso,por padrão,de fábrica|The printer works [out of the box] without configuration.
at stake|risk|em jogo,em risco|Our reputation is [at stake] in this negotiation.
by and large|generally|em geral,de modo geral|[By and large], the experiment was successful.
laissez-faire|nonintervention|laissez-faire,não intervenção|The minister favors a [laissez-faire] economic policy.
give|handover|dar,entregar|Please [give] the book to your sister.
bat|animal|morcego|A [bat] flew out of the cave at dusk.
bat|sport|taco|The baseball player swung his [bat].'''
lex = {}
for row in ROWS.splitlines():
    lemma, sense, pt, marked = row.split('|')
    a, b = marked.index('['), marked.index(']')
    sentence = marked.replace('[', '').replace(']', '')
    lex.setdefault(lemma, []).append({'senseId': sense, 'translations': pt.split(','),
        'prototypes': [{'sentence': sentence, 'start': a, 'end': b-1}]})

# categoria | seleção marcada | expressão gold | sentido | traduções aceitas
TEST = r'''phrasal_verb|I decided to [give] up programming.|give up|stop|desistir,abandonar
polysemy|Turn on the [light].|light|illumination|luz
technical|This framework is [light] and fast.|light|lightweight|leve,leve em recursos
polysemy|She deposited cash at the [bank].|bank|financial|banco
polysemy|The fisherman sat on the river [bank].|bank|river_edge|margem,beira
polysemy|There is no extra [charge] for delivery.|charge|fee|taxa,cobrança
polysemy|The phone needs a [charge].|charge|electricity|carga,carregar
polysemy|The prosecutor filed a [charge] of fraud.|charge|accusation|acusação
technical|We [run] automated tests every morning.|run|execute|executar,rodar
polysemy|I [run] five miles before breakfast.|run|jog|correr,corro
phrasal_verb|She will never [give] in to threats.|give in|yield|ceder
phrasal_verb|We plan to [give] away these books.|give away|donate|doar,dar,distribuir
phrasal_verb|Please [look] up this word in a dictionary.|look up|search|consultar,pesquisar,procurar
phrasal_verb|Can you [look] after my cat tomorrow?|look after|care|cuidar,cuidar de
phrasal_verb|They may [turn] down the job offer.|turn down|reject|recusar,rejeitar
phrasal_verb|Please [turn] down the music.|turn down|reduce|abaixar,diminuir,reduzir
phrasal_verb|Let us [set] up the development environment.|set up|establish|configurar,montar,criar
phrasal_verb|You should [carry] on with your studies.|carry on|continue|continuar,prosseguir
phrasal_verb|I often [run] into my teacher downtown.|run into|encounter|encontrar,encontro,esbarrar
technical|Each [thread] has its own stack.|thread|computing|thread,linha de execução
polysemy|The red [thread] broke while sewing.|thread|fiber|fio,linha
technical|Choose a web [framework] for this app.|framework|software|framework,estrutura
polysemy|The building has a wooden [framework].|framework|structure|estrutura,arcabouço
technical|A [race condition] corrupted the counter.|race condition|concurrency|condição de corrida,condição de disputa
technical|Use a [lock] to protect the shared resource.|lock|mutex|bloqueio,trava,mutex
polysemy|The door [lock] is broken.|lock|door|fechadura,tranca
technical|We will [deploy] the service tonight.|deploy|publish|implantar,publicar,implementar
technical|The latest [build] passed all checks.|build|software|compilação,construção
polysemy|They will [build] a bridge over the river.|build|construct|construir
technical|Create a new [branch] before editing code.|branch|git|ramificação,branch,ramo
polysemy|The falling [branch] damaged the car.|branch|tree|galho,ramo
technical|The next [release] fixes this bug.|release|version|versão,lançamento
polysemy|They will [release] the prisoner tomorrow.|release|free|libertar,soltar
technical|Save the current [state] before closing.|state|condition|estado
polysemy|Texas is a southern [state].|state|territory|estado
idiom|The values are calculated [on the fly].|on the fly|dynamic|dinamicamente,em tempo real,na hora
idiom|The software works [out of the box].|out of the box|ready|pronto para uso,por padrão,de fábrica
idiom|Several jobs are [at stake].|at stake|risk|em jogo,em risco
idiom|[By and large], customers like the update.|by and large|generally|em geral,de modo geral
idiom|He criticized the [laissez-faire] approach.|laissez-faire|nonintervention|laissez-faire,não intervenção
inflection|She [gave] up smoking last year.|give up|stop|desistiu,abandonou,desistir
inflection|He [looks] after his younger brother.|look after|care|cuida,cuidar,cuidar de
inflection|We [set] the new router up yesterday.|set up|establish|configuramos,configurar,montar
inflection|She [looked] the number up online.|look up|search|consultou,pesquisou,procurou,consultar
inflection|They [gave] the old furniture away.|give away|donate|doaram,doar,dar
negation|Do not [give] up now.|give up|stop|desistir,desista,abandonar
negation|We did not [run] the program.|run|execute|executar,rodar,executamos
punctuation|Mr. Smith said, "[Give] up the chase."|give up|stop|desistir,abandonar,desista
punctuation|The tool, e.g. a [framework], can help.|framework|software|framework,estrutura
punctuation|Please [give]\nup this dangerous habit.|give up|stop|desistir,abandonar
polysemy|This suitcase is surprisingly [light].|light|lightweight|leve
polysemy|Sunlight is a natural source of [light].|light|illumination|luz
polysemy|The [bank] refused the loan.|bank|financial|banco
polysemy|Willows grow along the [bank] of the river.|bank|river_edge|margem,beira
polysemy|A [bat] sleeps upside down.|bat|animal|morcego
polysemy|He hit the ball with a [bat].|bat|sport|taco
phrasal_verb|Please [give] the ticket to the driver.|give|handover|dar,entregar,dê
technical|We can [set up] a local database.|set up|establish|configurar,montar,criar
technical|The [race condition] disappears with synchronization.|race condition|concurrency|condição de corrida,condição de disputa
idiom|Their safety is [at stake] here.|at stake|risk|em jogo,em risco
abstain|The word [bank] has several meanings.|bank||
abstain|The invented word [florptastic] is unclear.|florptastic||
abstain|He said [charge] without any context.|charge||
abstain|Translate the isolated token [light].|light||'''
fixtures=[]
for i, row in enumerate(TEST.splitlines()):
    category, marked, expr, sense, pts = row.split('|')
    marked = marked.replace('\\n', '\n')
    a,b = marked.index('['),marked.index(']')
    sentence = marked.replace('[','').replace(']','')
    if expr == 'give away' and sense == 'donar,doar,dar': sense,pts='donate','doar,dar,distribuir'
    fixtures.append({'id': f'{category}-{i+1:03}', 'sentence':sentence,'selectedText':sentence[a:b-1],
        'start':a,'end':b-1,'expectedExpression':expr,'expectedSense':sense or None,
        'acceptableTranslationsPtBr':pts.split(',') if pts else [], 'category':category,
        'expectedAbstention':category=='abstain', 'provenance':'agent-authored-explicit-unvalidated', 'split':'test'})
for path,data in [('app/assets/lexicon.json',lex),('ml/datasets/evaluation.json',fixtures),('app/assets/evaluation.json',fixtures)]:
    dest=ROOT/path; dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
print(f'{len(fixtures)} fixtures; {sum(map(len,lex.values()))} protótipos; revisão humana pendente')
