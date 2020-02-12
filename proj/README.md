# Automatyczne skalowanie obliczeń w chmurze
<p align="center">
Rafał Pietruszka <br></br>
Mateusz Piwowarczyk
</p>

AWS Elastic Kubernetes Engine jest usługą pozwalającą na tworzenie oraz zarządzanie środowiskiem klastrów kubernetesa bez konieczności tworzenia własnej konfiguracji instancji maszyn EC2, sieci (VPC).


### 1. Wymagane oprogramowanie:
    

System linux z zainstalowanymi pakietami jq oraz curl.

Tworzenie oraz zarządzanie wszystkimi zasobami usługi EKS jest możliwe za pomocą następujących narzędzi:

1.  korzystając z portalu AWS Console,
    
2.  awscli, kubectl,
    
3.  narzędzia eksctl oraz kubectl.
    

Przedmiotem tego ćwiczenia jest narzędzie eksctl, które pozwala użytkownikowi stworzyć klaster w najprostszy sposób, zwalniając go z konieczności ręcznego definiowania zasobów takich jak: role IAM, grupy workernodów, sieci VPC, security groups, instancje EC2. Ponad to automatycznie definiuje publiczną podsieć która udostępnia API endpoint mastera Kubernetes, dzięki czemu od razu możemy korzystać z kubectl.

Jako pierwszy należu zainstalować pakiet awscli dla środowiska python. Ze względu na bliskie zakończenie wsparcia dla python2 oraz brak wymaganych funkcjonalności w wersjach <= 2.7.9 , zalecaną wersją jest python3. Pakiet zawiera aws-iam-authenticator wymagany dla eksctl:
```bash
python3 -m pip install awscli --upgrade --user  
aws configure #należy podać dane dla konta posiadającego uprawnienia do
```


  

Instalacja `eksctl`:
```bash
curl --silent --location https://github.com/weaveworks/eksctl/releases/download/

latest_release/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C ./  
mkdir -p $HOME/bin && cp ./eksctl $HOME/bin/eksctl && export PATH=$PATH:$HOME/bin
```
  

Instalacja `kubectl`:
```bash
curl -o kubectl https://amazon-eks.s3-us-west-2.amazonaws.com/1.14.6/2019-08-22/bin/linux/amd64/kubectl  
chmod +x ./kubectl  
cp ./kubectl $HOME/bin/kubectl
```
  

### 2. Tworzenie zarządzanego klastra EKS, z możliwością skalowania:
    

  

Dalsza część tutoriala rozważa jedynie wykorzystanie jedynie linuxowych maszyn wirtualnych dostępnych w darmowej opcji EC2.
```bash
eksctl  create  cluster  --name  eksMisows  --version  1.14  --region  eu-west-1  --nodegroup-name standard-workers  --node-type  t3.medium  --nodes  2  --nodes-min  1  --nodes-max  4  --ssh-access  --ssh-public-key  <key-name>  --managed --asg-access --vpc-nat-mode Disable
```
Istotnymi parametrami są:

|                  |                    |               |
|:----------------------------------:|:-------------------------------:|:--------------------:|
| `--name`|nazwa klastra         |unikalna           |
| `--region`          |region           |tutaj Irleand (eu-west-1)         |
|`--nodegroup-name`          |nazwa grupy nodów|istnieje możliwość zdefiniowania wielu grup np. dla różnych stref dostępności|
| `--node-type`|typ instancji EC2       |instancja nie powinna być mniejsza niż t2.small w przeciwnym przypadku mogą wystąpić problemy           |
| `--ssh-access --ssh-public-key`|nazwa istniejącego klucza dla ec2 lub plik      |opcjonalne, można pominąć           |


Tworzenie klastra zajmuje około 10 min, przykładowy efekt wywołania:

![](https://lh3.googleusercontent.com/VY_mO2IhktqGHq_dMmfFM3CWS1QPcnde7r6DOLiBJCTi_yXUM-VayJuJ15bhX3kOj6y1JxoZZYnX-tHESjZgnkPVcw-5XicmjzrgZ7JLEAgQx5Zq0UWWzejrEkg3jR00Cg)

Po jego utworzeniu należ sprawdzić czy narzędzie kubectl zostało uzupełnione konfiguracją stworzonego klastra:  
  
```bash
kubectl cluster-info  
  
#Przykładowy output  
Kubernetes master is running at https://148684264A26CD0EE8B8D79626CFB35F.yl4.eu-west-1.eks.amazonaws.com  
CoreDNS is running at https://148684264A26CD0EE8B8D79626CFB35F.yl4.eu-west-1.eks.amazonaws.com/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```
W przypadku problemów należy wykonać polecenie:
```bash
aws eks --region eu-west-1  update-kubeconfig --name eksMisows
```
  

### 3. Skalowanie na poziomie pod-ów.
    

  
Horizontal Pod Autoscaler odpowiada za automatyczne skalowanie podów, kontrolerów replik oraz zbiorów stanowych na podstawie monitorowanych metryk - obecnie powszechnie wspieraną i wykorzystywaną jest zużycie procesora podawaną jako zużycie(utilization) lub czas wykorzystania.

Do poprawnego działania wymagany jest serwis metrics-server odpowiadający za zbieranie i agregację wartości(w przypadku przypadku procentu wykorzystania jest to średnia) obiektów wykorzystywanych w zdefiniowanych metrykach.

Przybliżone zachowanie skalowania zasobu przez HPA opisuje wzór:  
  

docelowaIlośćReplik = ceil[obecnaIlośćReplik * ( obecnaWarośćMetryki / zadanaWarośćMetryki )]  
  

W przypadku zdefiniowania kilku metryk obliczane są wszystkie po po kolei, a za docelową ilość replik przyjmowana jest wartość maksymalna.

#### Instalacja metrics-servera:

  
```bash
DOWNLOAD_URL=$(curl -Ls "https://api.github.com/repos/kubernetes-sigs/metrics-server/releases/latest" | jq -r .tarball_url)  
DOWNLOAD_VERSION=$(grep -o '[^/v]*$' <<< $DOWNLOAD_URL)  
curl -Ls $DOWNLOAD_URL -o metrics-server-$DOWNLOAD_VERSION.tar.gz  
mkdir metrics-server-$DOWNLOAD_VERSION  
tar -xzf metrics-server-$DOWNLOAD_VERSION.tar.gz --directory metrics-server-$DOWNLOAD_VERSION --strip-components 1  
kubectl apply -f metrics-server-$DOWNLOAD_VERSION/deploy/1.8+/
```
 
Po poprawnym wykonaniu utworzony zostanie deployment, który jest widoczny przez:

```bash
kubectl get deployment metrics-server -n kube-system
```
Do prezentacji skalowania zostanie wykorzystany kontener z serwerem Apache:  
```bash
kubectl run httpd --image=httpd --requests=cpu=100m --limits=cpu=200m --expose --port=80
```
Definicja autoscalera dla deploymentu:
```bash
kubectl autoscale deployment httpd --cpu-percent=50 --min=1 --max=10
```
Deployment może posiadać od 1 do 10 replik, gdzie kryterium skanowania jest wykorzystanie 50% limitu cpu, gdy wartość wykorzystania spadnie poniżej ilość replik jestredukowana.  
Do wygenerowania obciążenia posłuży Apache Benchmark (zakończenie Ctrl+C):
```bash
kubectl  run  apache-bench  -i  --tty  --rm  --image=httpd  --  ab  -n  500000  -c  1000  http://httpd.default.svc.cluster.local/
```
Zmiany ilości replik oraz wartości metryki możemy obserwować poleceniem:
```bash
watch -n 5 -d 'kubectl describe hpa/httpd'
```
Przykładowy wynik:
![](https://lh4.googleusercontent.com/Yfum4Vws7WU8rSXcD4r-oIyz0YoEAKwSq_Ku2t7bqEP-yr4T5zSQGvh5DKnQbHnncBR0uQ9NiuiHmcC1A4mkXcGv2sEQqKDrGPFaOOrQEk-s8nFvxlFfj5PNSADmgAiKpQ)
    
 ### 4. Skalowanie klastra na poziomie węzłów.
Cluster Autoscaler jest mechanizmem Kubernetesa pozwalającym na dostosowywanie liczby węzłów w zależności od obciążenia klastra - błędy schedulingu podów spowodowane brakiem zasobów na obecnie działających węzłach klastra wyzwolą dodanie nowych.

  

Kluczowe dla działania tej funkcjonalności jest przypisanie roli IAM przypiętej do grupy worker nodów uprawnień:  
```json
"autoscaling:DescribeAutoScalingGroups",

"autoscaling:DescribeAutoScalingInstances",

"autoscaling:DescribeLaunchConfigurations",

"autoscaling:DescribeTags",

"autoscaling:SetDesiredCapacity",

"autoscaling:TerminateInstanceInAutoScalingGroup",

"ec2:DescribeLaunchTemplateVersions"
```
oraz tagowanie Auto Scaling Group w celu ich wykrycia przez EKS wartościami:  
  |        Tag       |          Wartość               |                      
|----------------------------|-------------------------------|
|`k8s.io/cluster-autoscaler/<cluster-name>`|owned          |
|`k8s.io/cluster-autoscaler/enabled  `         |true|


Tworząc klaster z wykorzystaniem eksctl powyższe wymagania są automatycznie spełnione.  
W celu utworzenia Cluster Autoscalera należy utworzyć deployment, który następnie zostanie oznaczony adnotacją safe-to-evict co zapobiega usuwaniu węzłów z działającymi podami.
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml  
  
kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"
```
Dla poprawnego działania wymagane jest również modyfikacja deployment-u w celu wykluczenia usuwania węzłów na których są uruchomione pod-y systemowe oraz w przypadku istnienia wielu grup worker nodów dla różnych stref równoważenia obciążenia wewnątrz nich:
```bash
kubectl -n kube-system  edit deployment.apps/cluster-autoscaler
```
Należy wyedytować sekcję spec.container.command aby zawierała następujące parametry:  
  ```yml
spec:
	containers:
		- command:
			- ./cluster-autoscaler
			- --v=4
			- --stderrthreshold=info
			- --cloud-provider=aws
			- --skip-nodes-with-local-storage=false
			- --expander=least-waste
			- --node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/eksMisows
			- --balance-similar-node-groups
			- --skip-nodes-with-system-pods=false  
  ```

Ostatnim krokiem jest wykonanie polecenia:
```bash
kubectl -n kube-system set image deployment.apps/cluster-autoscaler cluster-autoscaler=k8s.gcr.io/cluster-autoscaler:v1.14.7
```
Komunikaty Autoscalera są dostępne przez wykonanie:  
```bash
kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler
```
  

Do symulowania konieczności skalowania węzłów wykorzystamy deployment:
```bash
cat <<EoF> ./nginx.yaml  
apiVersion: apps/v1  
kind: Deployment  
metadata:  
    name: nginx-to-scaleout  
spec:  
    replicas:  1  
    selector:  
        matchLabels:  
        app: nginx  
    template:  
        metadata:  
        labels:  
        service: nginx  
        app: nginx  
        spec:  
        containers:  
        - image: nginx  
        name: nginx-to-scaleout  
        resources:  
            limits:  
            cpu:  500m  
            memory:  512Mi  
            requests:  
            cpu:  500m  
            memory:  512Mi  
EoF  
kubectl apply -f ./nginx.yaml  
kubectl get deployment/nginx-to-scaleout
```
  

Duży limit pamięci wymusi utworzenie dodatkowych nodów, teraz wymusimy replikację:
```bash
kubectl scale --replicas=10 deployment/nginx-to-scaleout
```
W logach Autoscalera pojawią się informacje dotyczące skalowania węzłów, przykładowo po usunięciu wszystkich replik deploymentu : 
```bash
kubectl delete -f ./nginx.yaml
```
powinne być zalogowane podobne informacje o zleceniu usunięcia nodów.  
  

![](https://lh4.googleusercontent.com/oT24mVbvyFb7whnh0fQHueW74iFEUGphcx18ZdiQiEiakLCZH52XUQXUKqod4CloOkI1ZGPc_VnAjNEGG4pkthV-vdIwXBEEJ8p6EaekOFj08VF8PQLJAdlURwY6iYmCYA)  
  

### 5.Usuwanie klastra i zasobów powiązanych.
    

W celu usunięcia klastra należy zwolnić wszystkie powiązane zasoby, należy rozpocząć od usług Kubernetesa skojarzonych z zewnętzeni dostępnym adresem IP:
```bash
kubectl get svc --all-namespaces
```
Następnie należy usunąć każdą usługę posiadającą wartość w kolumnie EXTERNAL-IP:
```bash
kubectl delete svc <service-name>
```
Ostatecznie możemy usunąć klaster:
```bash
eksctl delete cluster --name <cluster-name> --region=eu-west-2
```
Jeśli operacja zakończy się niepowodzeniem wciąż istnieją dodatkowe zasoby, które nie podlegają kontroli EKS i należy je ręcznie usunąć.

